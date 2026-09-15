"""The only module that imports bleak.

Everything the gateway does over the radio is four methods wide: find a
peripheral, connect to it, subscribe to its notifying characteristics, and
wait for the link to drop. Keeping them here, behind an interface the
supervisor calls, is what makes the rest of the program testable without a
controller.

bleak is a thin layer over the BlueZ D-Bus API on Linux, and the mapping is
worth knowing because it is what btmon and bluetoothctl show:

    BleakScanner(...)          org.bluez.Adapter1.SetDiscoveryFilter
                               org.bluez.Adapter1.StartDiscovery
    detection callback         InterfacesAdded, PropertiesChanged(RSSI)
    BleakClient.connect()      org.bluez.Device1.Connect, then a wait for
                               ServicesResolved to become true
    client.services            the object tree under the device path
    start_notify(char, cb)     GattCharacteristic1.StartNotify, which on
                               the wire is an ATT write of 0x0001 to the
                               client characteristic configuration
                               descriptor
    the notification callback  PropertiesChanged on Value

Written against bleak 0.21, which is what meta-python ships for this
release. The notification callback signature, `(characteristic, bytearray)`,
is the 0.20-and-later one; earlier bleak passed an integer handle, and code
written for it fails here in a way that looks like a protocol fault.

SPDX-License-Identifier: MIT
"""

import asyncio
import logging

from .bluest import SERVICE_UUID, mask_of

log = logging.getLogger("stwin-gw")


class BleakSession:
    """One connection, from Connected to the disconnect signal."""

    def __init__(self, client, address):
        self.client = client
        self.address = address
        self.closed = asyncio.Event()

    def _on_disconnect(self, _client):
        self.closed.set()

    async def subscribe(self, on_frame):
        """StartNotify on every notifying BlueST characteristic.

        Returns how many were subscribed, so that a peripheral with none
        is a decision for the supervisor rather than a silent success.
        """
        count = 0
        for service in self.client.services:
            if str(service.uuid).lower() != SERVICE_UUID:
                continue
            for char in service.characteristics:
                if "notify" not in char.properties:
                    continue
                mask = mask_of(char.uuid)
                if not mask:
                    continue

                # The mask is bound here, once, rather than looked up per
                # frame: it is a property of the characteristic and cannot
                # change while the connection lives.
                def handler(_char, data, mask=mask):
                    on_frame(mask, data, self.address)

                await self.client.start_notify(char, handler)
                log.info("subscribed %s", char.uuid)
                count += 1
        return count

    async def wait_closed(self):
        await self.closed.wait()

    async def close(self):
        if self.client.is_connected:
            await self.client.disconnect()


class BleakLink:
    def __init__(self, adapter=None, connect_timeout=15.0,
                 filter_uuid=False):
        self.adapter = adapter
        self.connect_timeout = connect_timeout
        self.filter_uuid = filter_uuid

    def _kwargs(self):
        return {"adapter": self.adapter} if self.adapter else {}

    async def scan(self, address, timeout, on_advertisement):
        """Scan until the wanted peripheral is seen, or the timeout.

        The scan is unfiltered by default, and that is a choice with a
        cost. A BlueZ discovery filter on the BlueST service UUID would
        wake this process less often, and it would also hide every
        advertisement that does not match, which is precisely the set you
        need to look at when the peripheral is not being found. Bring-up
        and range measurement both want to see everything; --filter-uuid
        turns the filter on once the link is known to work.

        Discovery is stopped before this returns, because an active scan
        running alongside a connection attempt shares the radio with it
        and turns a reliable connect into an intermittent one.
        """
        from bleak import BleakScanner

        found = asyncio.get_running_loop().create_future()
        wanted = address.lower() if address else None

        def detected(device, adv):
            on_advertisement(device.address, adv.rssi)
            if found.done():
                return
            if wanted is not None:
                if device.address.lower() == wanted:
                    found.set_result(device)
                return
            if SERVICE_UUID in [str(u).lower() for u in adv.service_uuids]:
                found.set_result(device)

        kwargs = self._kwargs()
        if self.filter_uuid:
            kwargs["service_uuids"] = [SERVICE_UUID]

        async with BleakScanner(detected, **kwargs):
            try:
                return await asyncio.wait_for(found, timeout)
            except asyncio.TimeoutError:
                return None

    async def connect(self, device):
        from bleak import BleakClient

        session_holder = {}

        def on_disconnect(client):
            session = session_holder.get("session")
            if session is not None:
                session._on_disconnect(client)

        client = BleakClient(device,
                             disconnected_callback=on_disconnect,
                             timeout=self.connect_timeout,
                             **self._kwargs())
        session = BleakSession(client, getattr(device, "address", str(device)))
        session_holder["session"] = session

        # connect() returns once ServicesResolved is true, which on a
        # peripheral with many characteristics is seconds rather than
        # milliseconds. The timeout covers that whole sequence, not just
        # the LE connection, which is why it is fifteen and not two.
        await client.connect()
        return session
