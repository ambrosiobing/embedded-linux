"""The connection state machine, with no radio in it.

Scanning, Connecting, Resolving, Streaming, Backoff. Every state maps to
one LED colour and to one line in the journal, and the whole thing is
driven through a `link` object with four methods. That indirection exists
for one reason: it is what lets the ladder, the back-off and the state
transitions be tested on a laptop, which is where the mistakes are, rather
than on a board, which is where they are expensive to find.

`blelink.BleakLink` is the real implementation and is thin enough to read
in one sitting. `tests/stwin-supervisor-test.sh` supplies a fake one that
can be told to fail at any step.

Two behaviours here are not in the original scope and are worth naming.

The first is that back-off is reset by *streaming*, not by connecting. A
peripheral that accepts a connection and then drops it immediately is a
peripheral the gateway would otherwise retry as fast as the radio allows,
for as long as the fault lasts. Resetting only once data has actually
arrived makes the ladder mean "how long since this link last worked".

The second is the stall timeout. A supervision timeout catches a link that
has gone away; it does not catch a peripheral that stays connected and
stops notifying, which is what a firmware that has crashed one task looks
like. Without this the gateway sits in Streaming with a green LED and
writes nothing, which is the worst of the failure modes because it looks
like success.

SPDX-License-Identifier: MIT
"""

import asyncio
import logging
import time

from .bluest import BluestError, decode, describe

log = logging.getLogger("stwin-gw")


class Supervisor:
    def __init__(self, link, sinks, address=None, scan_timeout=10.0,
                 backoff_start=1.0, backoff_max=30.0, stall_timeout=30.0,
                 sleep=None, clock=time.time):
        self.link = link
        self.sinks = list(sinks)
        self.address = address
        self.scan_timeout = scan_timeout
        self.backoff_start = backoff_start
        self.backoff_max = backoff_max
        self.stall_timeout = stall_timeout
        self.sleep = sleep if sleep is not None else asyncio.sleep
        self.clock = clock

        self.backoff = backoff_start
        self.state = None
        self.frames = 0
        self.last_frame = 0.0
        self.decode_errors = 0

    # ------------------------------------------------------------- sinks

    def _state(self, name):
        self.state = name
        for sink in self.sinks:
            sink.state(name)

    def _advertisement(self, address, rssi):
        # RSSI is logged here and nowhere else, because here is the only
        # place it is real. org.bluez.Device1's RSSI property is fed by
        # advertising reports and is not refreshed while a device is
        # connected, so a gateway that reports "current RSSI" during a
        # session is reporting a number from before the connection. The
        # honest figure is the one from the last advertisement seen before
        # each connect, and that is what these records are.
        when = self.clock()
        for sink in self.sinks:
            sink.rssi(address, rssi, when)

    def _frame(self, mask, data, address):
        self.frames += 1
        self.last_frame = self.clock()
        try:
            record = decode(mask, bytes(data))
        except BluestError as error:
            # One line per fault, not one per frame: a peripheral whose
            # frames do not match this table produces fifty of these a
            # second, and a journal full of identical lines is a journal
            # nobody reads.
            self.decode_errors += 1
            if self.decode_errors == 1 or self.decode_errors % 100 == 0:
                log.warning("undecodable frame on %s (%d so far): %s",
                            describe(mask), self.decode_errors, error)
            return
        record["mask"] = mask
        record["mac"] = address
        record["host_ts"] = self.last_frame
        for sink in self.sinks:
            sink.write(record)

    # ------------------------------------------------------------- the loop

    async def _back_off(self):
        self._state("backoff")
        delay = self.backoff
        self.backoff = min(self.backoff * 2, self.backoff_max)
        log.info("retrying in %.0f s", delay)
        await self.sleep(delay)

    async def _stream(self, session):
        """Wait for the link to drop, or for it to go quiet."""
        closed = asyncio.ensure_future(session.wait_closed())
        try:
            while True:
                if not self.stall_timeout:
                    await closed
                    return "disconnected"

                done, _pending = await asyncio.wait(
                    {closed}, timeout=self.stall_timeout)
                if closed in done:
                    return "disconnected"
                quiet = self.clock() - self.last_frame
                if quiet >= self.stall_timeout:
                    # %.1f, not %.0f: with a short stall timeout the
                    # rounded form says "no frame for 0 s", which reads
                    # like a bug in the check rather than a quiet link.
                    log.warning("connected but no frame for %.1f s, "
                                "treating the link as dead", quiet)
                    return "stalled"
        finally:
            if not closed.done():
                closed.cancel()

    async def run(self, rounds=None):
        """Run the ladder. `rounds` bounds it, for tests."""
        completed = 0
        while rounds is None or completed < rounds:
            completed += 1
            session = None
            try:
                self._state("scanning")
                device = await self.link.scan(
                    self.address, self.scan_timeout, self._advertisement)
                if device is None:
                    log.info("no advertisement in %.0f s", self.scan_timeout)
                    await self._back_off()
                    continue

                self._state("connecting")
                session = await self.link.connect(device)

                self._state("resolving")
                subscribed = await session.subscribe(self._frame)
                if not subscribed:
                    # Connected, services resolved, and not one notifying
                    # characteristic under the BlueST service. That is a
                    # peripheral running firmware this gateway does not
                    # understand, and retrying it forever at the fastest
                    # rate the radio allows helps nobody.
                    log.warning("no notifying BlueST characteristic found")
                    await self._back_off()
                    continue

                log.info("streaming %d characteristic(s)", subscribed)
                self.last_frame = self.clock()
                self._state("streaming")
                self.backoff = self.backoff_start

                reason = await self._stream(session)
                log.info("link ended: %s, %d frames", reason, self.frames)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                # Deliberately broad. Every exception a BLE stack raises is
                # a reason to go back to Scanning, and a gateway that exits
                # on an unexpected one is a gateway that needs a person.
                # The type and message are logged so that a recurring fault
                # is still diagnosable from the journal.
                log.warning("link error: %s: %s",
                            type(error).__name__, error)
            finally:
                if session is not None:
                    try:
                        await session.close()
                    except Exception as error:
                        log.debug("close failed: %s", error)

            await self._back_off()

        return completed

    def close(self):
        self._state("off")
        for sink in self.sinks:
            sink.close()
