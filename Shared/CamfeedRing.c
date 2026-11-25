//
//  CamfeedRing.c
//

#include "CamfeedRing.h"

#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

_Static_assert(CF_SLOT_BYTES % 64 == 0, "slots must stay cache line aligned");

/* Only one producer exists per ring, so the slot being filled can live in a file static. */
static uint32_t g_writeSlot;

size_t camfeed_ring_bytes(void)
{
	return CF_RING_DATA_OFFSET + (size_t)CF_RING_SLOTS * CF_SLOT_BYTES;
}

int camfeed_ring_open(const char *path, int create)
{
	int flags = O_RDWR;
	if (create) {
		flags |= O_CREAT;
	}
	int fd = open(path, flags, 0666);
	/* Producer and consumer run under different uids, so whichever opened first must not lock the other out. */
	if (fd >= 0) {
		fchmod(fd, 0666);
	}
	return fd;
}

int camfeed_ring_prepare(int fd, void *base)
{
	size_t length = camfeed_ring_bytes();
	struct stat st;

	if (fstat(fd, &st) != 0) {
		return -1;
	}
	if ((size_t)st.st_size != length && ftruncate(fd, (off_t)length) != 0) {
		return -1;
	}

	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	if (atomic_load_explicit(&header->magic, memory_order_acquire) == CF_RING_MAGIC) {
		return 0;
	}

	memset(base, 0, CF_RING_DATA_OFFSET);
	atomic_store(&header->slotCount, CF_RING_SLOTS);
	atomic_store(&header->bytesPerSlot, (uint32_t)CF_SLOT_BYTES);
	atomic_store(&header->requestedWidth, 0);
	atomic_store(&header->requestedHeight, 0);
	atomic_store_explicit(&header->magic, CF_RING_MAGIC, memory_order_release);
	return 0;
}

void *camfeed_ring_map(int fd)
{
	void *base = mmap(NULL, camfeed_ring_bytes(), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	return base == MAP_FAILED ? NULL : base;
}

void camfeed_ring_unmap(int fd, void *base)
{
	if (base != NULL) {
		munmap(base, camfeed_ring_bytes());
	}
	if (fd >= 0) {
		close(fd);
	}
}

uint8_t *camfeed_ring_begin_write(void *base)
{
	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	uint32_t seq = atomic_load_explicit(&header->writeSeq, memory_order_relaxed);
	g_writeSlot = seq % CF_RING_SLOTS;
	return (uint8_t *)base + CF_RING_DATA_OFFSET + (size_t)g_writeSlot * CF_SLOT_BYTES;
}

void camfeed_ring_commit_write(void *base, uint32_t width, uint32_t height)
{
	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	atomic_store_explicit(&header->frameWidth[g_writeSlot], width, memory_order_relaxed);
	atomic_store_explicit(&header->frameHeight[g_writeSlot], height, memory_order_relaxed);
	atomic_fetch_add_explicit(&header->writeSeq, 1, memory_order_release);
}

int camfeed_ring_read_latest(void *base, uint8_t **data, uint32_t *width, uint32_t *height)
{
	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	uint32_t seq = atomic_load_explicit(&header->writeSeq, memory_order_acquire);
	if (seq == 0) {
		return 0;
	}

	uint32_t slot = (seq - 1) % CF_RING_SLOTS;
	uint32_t slotWidth = atomic_load_explicit(&header->frameWidth[slot], memory_order_relaxed);
	uint32_t slotHeight = atomic_load_explicit(&header->frameHeight[slot], memory_order_relaxed);

	/* The producer would have to run CF_RING_SLOTS frames ahead to reuse this slot mid-copy. */
	if (atomic_load_explicit(&header->writeSeq, memory_order_acquire) - seq >= CF_RING_SLOTS) {
		return 0;
	}
	if (slotWidth == 0 || slotHeight == 0 || slotWidth > CF_RING_MAX_WIDTH || slotHeight > CF_RING_MAX_HEIGHT) {
		return 0;
	}

	*data = (uint8_t *)base + CF_RING_DATA_OFFSET + (size_t)slot * CF_SLOT_BYTES;
	*width = slotWidth;
	*height = slotHeight;
	return 1;
}

void camfeed_ring_set_requested_format(void *base, uint32_t width, uint32_t height)
{
	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	atomic_store_explicit(&header->requestedWidth, width, memory_order_seq_cst);
	atomic_store_explicit(&header->requestedHeight, height, memory_order_seq_cst);
}

void camfeed_ring_get_requested_format(void *base, uint32_t *width, uint32_t *height)
{
	CamfeedRingHeader *header = (CamfeedRingHeader *)base;
	*width = atomic_load_explicit(&header->requestedWidth, memory_order_seq_cst);
	*height = atomic_load_explicit(&header->requestedHeight, memory_order_seq_cst);
}
