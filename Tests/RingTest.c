#include "CamfeedRing.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
	char path[] = "/tmp/camfeed-ring-test.bin";
	remove(path);
	int fd = camfeed_ring_open(path, 1);
	assert(fd >= 0);
	void *base = camfeed_ring_map(fd);
	assert(base && camfeed_ring_prepare(fd, base) == 0);

	uint8_t *data = NULL;
	uint32_t w = 0, h = 0;
	assert(camfeed_ring_read_latest(base, &data, &w, &h) == 0);

	memset(camfeed_ring_begin_write(base), 0xAA, 1920 * 1080 * 4);
	camfeed_ring_commit_write(base, 1920, 1080);
	assert(camfeed_ring_read_latest(base, &data, &w, &h) == 1);
	assert(w == 1920 && h == 1080 && data[0] == 0xAA);

	memset(camfeed_ring_begin_write(base), 0xBB, 1280 * 720 * 4);
	camfeed_ring_commit_write(base, 1280, 720);
	assert(camfeed_ring_read_latest(base, &data, &w, &h) == 1);
	assert(w == 1280 && h == 720 && data[0] == 0xBB);

	camfeed_ring_set_requested_format(base, 1280, 720);
	uint32_t rw = 0, rh = 0;
	camfeed_ring_get_requested_format(base, &rw, &rh);
	assert(rw == 1280 && rh == 720);

	/* Stale frame must be dropped once the producer laps the reader. */
	for (int i = 0; i < CF_RING_SLOTS; i++) {
		camfeed_ring_begin_write(base);
		camfeed_ring_commit_write(base, 1920, 1080);
	}
	assert(camfeed_ring_read_latest(base, &data, &w, &h) == 1);
	assert(w == 1920 && h == 1080);

	camfeed_ring_unmap(fd, base);

	/* The extension opens the same file and sees the last committed frame. */
	fd = camfeed_ring_open(path, 0);
	base = camfeed_ring_map(fd);
	assert(base && camfeed_ring_prepare(fd, base) == 0);
	assert(camfeed_ring_read_latest(base, &data, &w, &h) == 1);
	assert(w == 1920 && h == 1080);
	camfeed_ring_unmap(fd, base);
	remove(path);
	printf("ring ok\n");
	return 0;
}
