// SPDX-License-Identifier: GPL-2.0-only
/*
 * buggy: four deliberate kernel faults, one per write to a debugfs file.
 *
 * This module exists to be wrong. It is the subject of Project 9, whose
 * point is that three of these four faults produce no symptom at the
 * moment they happen, so the tool that finds each one has to be in place
 * and understood beforehand.
 *
 *     echo null > /sys/kernel/debug/buggy/trigger
 *     echo lock > /sys/kernel/debug/buggy/trigger
 *     echo uaf  > /sys/kernel/debug/buggy/trigger
 *     echo leak > /sys/kernel/debug/buggy/trigger
 *
 * WHAT EACH ONE DOES AND WHAT FINDS IT
 *
 *   null   Dereferences a NULL pointer. Oopses immediately, and with
 *          CONFIG_PANIC_ON_OOPS panics and reboots. Found by the console,
 *          then by pstore after the reboot, then live under kgdb. This is
 *          the easy one and it is first for that reason.
 *
 *   lock   Takes a spinlock with interrupts disabled and holds it for
 *          three seconds. No oops, no message, no crash: the system is
 *          simply late. Found by the irqsoff tracer, which reports how
 *          long and where, and complained about by the soft lockup
 *          detector once the threshold passes.
 *
 *   uaf    Writes through a pointer after freeing it. Usually nothing
 *          happens, because freed memory is usually still mapped and
 *          often still holds the old value. Found by KASAN, which
 *          reports the allocation site and the free site with stacks.
 *          Without KASAN this reads correctly most times and wrongly
 *          occasionally, which is the worst behaviour a bug can have.
 *
 *   leak   Allocates 64 objects of 256 bytes and drops every pointer.
 *          Nothing happens, ever, until the box runs out of memory in a
 *          month. Found by kmemleak, after a scan, which reports it as
 *          64 unreferenced objects.
 *
 * ON PURPOSE, AND WORTH SAYING OUT LOUD
 *
 * Every fault is behind an explicit keyword on a write-only file, and
 * nothing here fires at module load. A fault injector that did something
 * when it was installed would make "modprobe buggy" on the wrong board a
 * reboot, and this module is on an image whose whole purpose is to be
 * loaded on a board that is being investigated.
 *
 * The functions are noinline and their names are the ones the notebook
 * sets breakpoints on. Do not let them be folded together: identical code
 * folding would give two faults one address, and the backtrace would name
 * the wrong one confidently.
 */

#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/uaccess.h>

#define BUGGY_DIR	"buggy"

/*
 * 64 objects of 256 bytes, not one block of 16 kB, although the total is
 * the same. kmemleak reports objects rather than bytes, so the shape of
 * the allocation is what the acceptance criterion can be written
 * against: "64 unreferenced objects" is checkable, and "16 kB leaked" is
 * not, because kmemleak never prints that number.
 */
#define LEAK_OBJECTS	64
#define LEAK_OBJECT_SZ	256
#define LOCK_HOLD_MS	3000

/*
 * The thing the null fault dereferences. It is a file-scope volatile
 * pointer rather than a literal NULL in the expression, for two reasons:
 * the compiler cannot fold the dereference away as undefined behaviour,
 * and there is a named symbol for the notebook to inspect. Under kgdb,
 *
 *     print victim
 *
 * shows 0x0, which is the difference between reading a backtrace and
 * seeing the cause.
 */
struct buggy_thing {
	unsigned long	magic;
	char		name[16];
};

static struct buggy_thing *volatile victim;

static DEFINE_SPINLOCK(buggy_lock);

static struct dentry *buggy_dir;

/* Fault 1: NULL dereference. Announces itself. */
static noinline void fault_null(void)
{
	pr_info("buggy: about to dereference %px\n", victim);

	/*
	 * victim is never assigned, so it is NULL. The write, not the
	 * read, so that the oops names a write and the notebook can
	 * check that the fault address and the direction both match.
	 */
	victim->magic = 0x1234;

	pr_info("buggy: unreachable\n");
}

/* Fault 2: interrupts off for three seconds. Says nothing at all. */
static noinline void fault_lock(void)
{
	unsigned long flags;

	pr_info("buggy: holding a spinlock with interrupts off for %d ms\n",
		LOCK_HOLD_MS);

	spin_lock_irqsave(&buggy_lock, flags);

	/*
	 * mdelay, not msleep. msleep would schedule, which is exactly
	 * what cannot happen here: the fault being demonstrated is a
	 * busy wait with interrupts disabled, and a sleeping version of
	 * it would be a different and much less interesting bug.
	 *
	 * The heartbeat LED keeps beating through this, because the
	 * timer driving it runs on another core. That is worth watching
	 * once: the instrument that usually means "alive" says "alive"
	 * while one core is entirely stuck.
	 */
	mdelay(LOCK_HOLD_MS);

	spin_unlock_irqrestore(&buggy_lock, flags);

	pr_info("buggy: released, and nothing was reported\n");
}

/* Fault 3: use after free. Usually silent, and wrong at random. */
static noinline void fault_uaf(void)
{
	struct buggy_thing *thing;

	thing = kmalloc(sizeof(*thing), GFP_KERNEL);
	if (!thing)
		return;

	thing->magic = 0xdeadbeef;
	kfree(thing);

	/*
	 * The access that KASAN reports. Without KASAN this very often
	 * succeeds and prints 0xdeadbeef, because the allocator has not
	 * reused the object yet, which is precisely why a use after free
	 * can live in a tree for years.
	 */
	pr_info("buggy: reading freed memory, magic is 0x%lx\n", thing->magic);
	thing->magic = 0;
}

/* Fault 4: a leak. Silent forever. */
static noinline void fault_leak(void)
{
	unsigned int i;
	unsigned int leaked = 0;

	for (i = 0; i < LEAK_OBJECTS; i++) {
		void *block;

		block = kmalloc(LEAK_OBJECT_SZ, GFP_KERNEL);
		if (!block)
			break;

		/*
		 * Touch it so the allocation is real, then drop the only
		 * pointer to it. kmemleak scans memory for values that
		 * look like pointers to tracked blocks, so keeping these
		 * in a file-scope array would make every one of them
		 * reachable and the leak invisible. That mistake is worth
		 * naming because it does not fail: the scan simply comes
		 * back clean and the tool looks like it does not work.
		 */
		memset(block, 0xa5, LEAK_OBJECT_SZ);
		leaked++;
	}

	pr_info("buggy: leaked %u objects of %d bytes; "
		"echo scan > /sys/kernel/debug/kmemleak to see them\n",
		leaked, LEAK_OBJECT_SZ);
}

static const struct {
	const char	*name;
	void		(*fn)(void);
} faults[] = {
	{ "null", fault_null },
	{ "lock", fault_lock },
	{ "uaf",  fault_uaf  },
	{ "leak", fault_leak },
};

static ssize_t trigger_write(struct file *file, const char __user *buf,
			     size_t len, loff_t *ppos)
{
	char command[16];
	char *keyword;
	size_t taken;
	unsigned int i;

	if (len == 0)
		return -EINVAL;

	taken = min(len, sizeof(command) - 1);
	if (copy_from_user(command, buf, taken))
		return -EFAULT;
	command[taken] = '\0';

	/*
	 * strim returns the start of the trimmed string, which is NOT
	 * necessarily the buffer it was given: it skips leading
	 * whitespace by returning a pointer further in. Discarding that
	 * return value and comparing the original buffer would make
	 * "echo ' null'" fail to match, for a reason nothing on the
	 * console would explain.
	 */
	keyword = strim(command);

	for (i = 0; i < ARRAY_SIZE(faults); i++) {
		if (strcmp(keyword, faults[i].name) == 0) {
			pr_info("buggy: triggering %s\n", faults[i].name);
			faults[i].fn();
			return len;
		}
	}

	/*
	 * An unknown keyword is an error rather than a no-op, and it
	 * lists what it would have accepted. A fault injector that
	 * accepted a typo silently would let an evening go by with the
	 * conclusion "the tool found nothing", which is the same shape as
	 * a working tool reporting a clean run.
	 */
	pr_warn("buggy: unknown trigger \"%s\"; try one of: null lock uaf leak\n",
		keyword);
	return -EINVAL;
}

static const struct file_operations trigger_fops = {
	.owner	= THIS_MODULE,
	.write	= trigger_write,
	.llseek	= noop_llseek,
};

static int __init buggy_init(void)
{
	buggy_dir = debugfs_create_dir(BUGGY_DIR, NULL);
	if (IS_ERR(buggy_dir))
		return PTR_ERR(buggy_dir);

	/* 0200: write only. There is nothing to read, and a readable file
	 * would invite a cat that does nothing and reads like a failure.
	 */
	debugfs_create_file("trigger", 0200, buggy_dir, NULL, &trigger_fops);

	pr_info("buggy: loaded, nothing has happened yet\n");
	pr_info("buggy: echo {null|lock|uaf|leak} > /sys/kernel/debug/%s/trigger\n",
		BUGGY_DIR);
	return 0;
}

static void __exit buggy_exit(void)
{
	debugfs_remove_recursive(buggy_dir);

	/*
	 * The leaked blocks are deliberately not freed here. Freeing them
	 * on unload would make the leak a property of module lifetime
	 * rather than a leak, and kmemleak would have nothing to report
	 * on a board where the module was removed before the scan.
	 */
	pr_info("buggy: unloaded; any leaked blocks are still leaked\n");
}

module_init(buggy_init);
module_exit(buggy_exit);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Four deliberate kernel faults for the Project 9 debugging lab");
