//
//  CamfeedRing.h
//  Single-producer/single-consumer frame ring shared between the Camfeed app and its camera extension.
//

#ifndef CAMFEED_RING_H
#define CAMFEED_RING_H

#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>

#define CF_RING_MAGIC 0x43464D52u /* 'CFMR' */
#define CF_RING_SLOTS 4
#define CF_RING_MAX_WIDTH 1920
#define CF_RING_MAX_HEIGHT 1080
#define CF_RING_BYTES_PER_PIXEL 4
#define CF_RING_DATA_OFFSET 4096
#define CF_SLOT_BYTES ((size_t)CF_RING_MAX_WIDTH * CF_RING_MAX_HEIGHT * CF_RING_BYTES_PER_PIXEL)

typedef struct {
	_Atomic uint32_t magic;
	_Atomic uint32_t slotCount;
	_Atomic uint32_t bytesPerSlot;

	/* Published by the extension when a client picks a stream format, read by the app. */
	_Atomic uint32_t requestedWidth;
	_Atomic uint32_t requestedHeight;

	/* Incremented by the app once a frame is fully written to its slot. */
	_Atomic uint32_t writeSeq;

	_Atomic uint32_t frameWidth[CF_RING_SLOTS];
	_Atomic uint32_t frameHeight[CF_RING_SLOTS];
} CamfeedRingHeader;

/// Total mapping length, header page included.
size_t camfeed_ring_bytes(void);

/// Opens (and optionally creates) the ring file. Returns a fd or -1.
int camfeed_ring_open(const char *path, int create);

/// Sizes the file and resets the header when it is not already initialised. Returns 0 on success.
int camfeed_ring_prepare(int fd, void *base);

/// Maps the ring read/write shared. Returns NULL on failure.
void *camfeed_ring_map(int fd);

void camfeed_ring_unmap(int fd, void *base);

/// Returns the slot the next frame must be written into. The slot has CF_SLOT_BYTES bytes.
uint8_t *camfeed_ring_begin_write(void *base);

/// Publishes the frame written by the last begin_write call.
void camfeed_ring_commit_write(void *base, uint32_t width, uint32_t height);

/// Returns 1 and fills the arguments when a complete frame is available.
int camfeed_ring_read_latest(void *base, uint8_t **data, uint32_t *width, uint32_t *height);

void camfeed_ring_set_requested_format(void *base, uint32_t width, uint32_t height);
void camfeed_ring_get_requested_format(void *base, uint32_t *width, uint32_t *height);

#endif /* CAMFEED_RING_H */
