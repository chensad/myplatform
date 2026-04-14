#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define EEPROM24C16_DEFAULT_BUS 0
#define EEPROM24C16_DEFAULT_BASE_ADDR 0x50
#define EEPROM24C16_TOTAL_SIZE 2048
#define EEPROM24C16_BLOCK_SIZE 256
#define EEPROM24C16_NUM_BLOCKS 8
#define EEPROM24C16_PAGE_SIZE 16

struct app_config {
	int bus;
	int base_addr;
};

static void print_usage(const char *prog)
{
	printf("Usage:\n");
	printf("  %s [--bus N] [--base-addr 0x50] read <offset> <len>\n", prog);
	printf("  %s [--bus N] [--base-addr 0x50] write <offset> <byte> [byte...]\n", prog);
	printf("  %s [--bus N] [--base-addr 0x50] dump [offset] [len]\n", prog);
	printf("\n");
	printf("Notes:\n");
	printf("  - 24C16 is 2048 bytes total, split across I2C addresses 0x50-0x57.\n");
	printf("  - Offsets may be decimal or hex, for example 0x120.\n");
	printf("  - Writes are split automatically on 16-byte page boundaries.\n");
	printf("\n");
	printf("Examples:\n");
	printf("  %s read 0x000 16\n", prog);
	printf("  %s write 0x010 0x11 0x22 0x33 0x44\n", prog);
	printf("  %s dump 0x000 64\n", prog);
}

static int parse_number(const char *text, int *value)
{
	char *end;
	long parsed;

	parsed = strtol(text, &end, 0);
	if (*text == '\0' || *end != '\0') {
		fprintf(stderr, "invalid number: %s\n", text);
		return -1;
	}
	*value = (int)parsed;
	return 0;
}

static int validate_range(int offset, int len)
{
	if (offset < 0 || offset >= EEPROM24C16_TOTAL_SIZE) {
		fprintf(stderr, "offset out of range: %d (valid 0..%d)\n",
			offset, EEPROM24C16_TOTAL_SIZE - 1);
		return -1;
	}
	if (len < 0 || offset + len > EEPROM24C16_TOTAL_SIZE) {
		fprintf(stderr, "range out of EEPROM: offset=%d len=%d size=%d\n",
			offset, len, EEPROM24C16_TOTAL_SIZE);
		return -1;
	}
	return 0;
}

static int open_i2c_bus(int bus)
{
	char path[32];
	int fd;

	snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
	fd = open(path, O_RDWR);
	if (fd < 0)
		perror(path);
	return fd;
}

static int set_slave_addr(int fd, int addr)
{
	if (ioctl(fd, I2C_SLAVE, addr) < 0) {
		fprintf(stderr, "failed to select I2C address 0x%02x: %s\n",
			addr, strerror(errno));
		return -1;
	}
	return 0;
}

static int offset_to_addr(const struct app_config *cfg, int offset, int *addr, int *reg)
{
	if (validate_range(offset, 1) < 0)
		return -1;

	*addr = cfg->base_addr + (offset / EEPROM24C16_BLOCK_SIZE);
	*reg = offset % EEPROM24C16_BLOCK_SIZE;
	return 0;
}

static int eeprom_wait_ready(int fd, int addr)
{
	int tries;
	uint8_t reg = 0;
	struct i2c_msg msg = {
		.addr = addr,
		.flags = 0,
		.len = 1,
		.buf = &reg,
	};
	struct i2c_rdwr_ioctl_data rdwr = {
		.msgs = &msg,
		.nmsgs = 1,
	};

	for (tries = 0; tries < 100; ++tries) {
		if (ioctl(fd, I2C_RDWR, &rdwr) == 1)
			return 0;
		usleep(5000);
	}

	fprintf(stderr, "EEPROM write-cycle wait timed out on 0x%02x: %s\n",
		addr, strerror(errno));
	return -1;
}

static int eeprom_read_chunk(int fd, const struct app_config *cfg, int offset,
			     uint8_t *buf, int len)
{
	int addr;
	int reg;
	uint8_t reg_buf;
	struct i2c_msg msgs[2];
	struct i2c_rdwr_ioctl_data rdwr;

	if (offset_to_addr(cfg, offset, &addr, &reg) < 0)
		return -1;

	reg_buf = (uint8_t)reg;
	msgs[0].addr = addr;
	msgs[0].flags = 0;
	msgs[0].len = 1;
	msgs[0].buf = &reg_buf;

	msgs[1].addr = addr;
	msgs[1].flags = I2C_M_RD;
	msgs[1].len = (uint16_t)len;
	msgs[1].buf = buf;

	rdwr.msgs = msgs;
	rdwr.nmsgs = 2;

	if (ioctl(fd, I2C_RDWR, &rdwr) != 2) {
		fprintf(stderr, "EEPROM read failed at offset 0x%03x: %s\n",
			offset, strerror(errno));
		return -1;
	}
	return 0;
}

static int eeprom_write_chunk(int fd, const struct app_config *cfg, int offset,
			      const uint8_t *buf, int len)
{
	int addr;
	int reg;
	uint8_t msg_buf[1 + EEPROM24C16_PAGE_SIZE];
	struct i2c_msg msg;
	struct i2c_rdwr_ioctl_data rdwr;

	if (offset_to_addr(cfg, offset, &addr, &reg) < 0)
		return -1;
	if (len < 0 || len > EEPROM24C16_PAGE_SIZE) {
		fprintf(stderr, "invalid write chunk size: %d\n", len);
		return -1;
	}

	msg_buf[0] = (uint8_t)reg;
	memcpy(&msg_buf[1], buf, (size_t)len);

	msg.addr = addr;
	msg.flags = 0;
	msg.len = (uint16_t)(len + 1);
	msg.buf = msg_buf;

	rdwr.msgs = &msg;
	rdwr.nmsgs = 1;

	if (ioctl(fd, I2C_RDWR, &rdwr) != 1) {
		fprintf(stderr, "EEPROM write failed at offset 0x%03x: %s\n",
			offset, strerror(errno));
		return -1;
	}

	return eeprom_wait_ready(fd, addr);
}

static int eeprom_read(int fd, const struct app_config *cfg, int offset,
		       uint8_t *buf, int len)
{
	int remaining = len;
	int chunk;
	int cursor = offset;

	if (validate_range(offset, len) < 0)
		return -1;

	while (remaining > 0) {
		chunk = EEPROM24C16_BLOCK_SIZE - (cursor % EEPROM24C16_BLOCK_SIZE);
		if (chunk > remaining)
			chunk = remaining;

		if (eeprom_read_chunk(fd, cfg, cursor, buf, chunk) < 0)
			return -1;

		cursor += chunk;
		buf += chunk;
		remaining -= chunk;
	}

	return 0;
}

static int eeprom_write(int fd, const struct app_config *cfg, int offset,
			const uint8_t *buf, int len)
{
	int remaining = len;
	int chunk;
	int page_left;
	int block_left;
	int cursor = offset;

	if (validate_range(offset, len) < 0)
		return -1;

	while (remaining > 0) {
		page_left = EEPROM24C16_PAGE_SIZE - (cursor % EEPROM24C16_PAGE_SIZE);
		block_left = EEPROM24C16_BLOCK_SIZE - (cursor % EEPROM24C16_BLOCK_SIZE);
		chunk = page_left;
		if (chunk > block_left)
			chunk = block_left;
		if (chunk > remaining)
			chunk = remaining;

		if (eeprom_write_chunk(fd, cfg, cursor, buf, chunk) < 0)
			return -1;

		cursor += chunk;
		buf += chunk;
		remaining -= chunk;
	}

	return 0;
}

static void print_hex_dump(int start_offset, const uint8_t *buf, int len)
{
	int row;
	int col;

	for (row = 0; row < len; row += 16) {
		printf("%03x: ", start_offset + row);
		for (col = 0; col < 16; ++col) {
			if (row + col < len)
				printf("%02x ", buf[row + col]);
			else
				printf("   ");
		}
		printf(" |");
		for (col = 0; col < 16 && row + col < len; ++col) {
			uint8_t ch = buf[row + col];
			printf("%c", (ch >= 32 && ch <= 126) ? ch : '.');
		}
		printf("|\n");
	}
}

static int cmd_read(int fd, const struct app_config *cfg, int argc, char **argv)
{
	int offset;
	int len;
	uint8_t *buf;
	int i;

	if (argc != 2) {
		fprintf(stderr, "read requires <offset> <len>\n");
		return -1;
	}
	if (parse_number(argv[0], &offset) < 0 || parse_number(argv[1], &len) < 0)
		return -1;
	if (len <= 0) {
		fprintf(stderr, "read length must be > 0\n");
		return -1;
	}

	buf = malloc((size_t)len);
	if (!buf) {
		perror("malloc");
		return -1;
	}

	if (eeprom_read(fd, cfg, offset, buf, len) < 0) {
		free(buf);
		return -1;
	}

	printf("Read %d bytes from EEPROM offset 0x%03x\n", len, offset);
	for (i = 0; i < len; ++i)
		printf("%02x%s", buf[i], (i + 1 == len) ? "\n" : " ");
	free(buf);
	return 0;
}

static int cmd_dump(int fd, const struct app_config *cfg, int argc, char **argv)
{
	int offset = 0;
	int len = 128;
	uint8_t *buf;

	if (argc > 0 && parse_number(argv[0], &offset) < 0)
		return -1;
	if (argc > 1 && parse_number(argv[1], &len) < 0)
		return -1;
	if (argc > 2) {
		fprintf(stderr, "dump accepts at most [offset] [len]\n");
		return -1;
	}
	if (len <= 0) {
		fprintf(stderr, "dump length must be > 0\n");
		return -1;
	}

	buf = malloc((size_t)len);
	if (!buf) {
		perror("malloc");
		return -1;
	}

	if (eeprom_read(fd, cfg, offset, buf, len) < 0) {
		free(buf);
		return -1;
	}

	printf("EEPROM dump from 0x%03x, %d bytes\n", offset, len);
	print_hex_dump(offset, buf, len);
	free(buf);
	return 0;
}

static int cmd_write(int fd, const struct app_config *cfg, int argc, char **argv)
{
	int offset;
	int i;
	int value;
	uint8_t *buf;

	if (argc < 2) {
		fprintf(stderr, "write requires <offset> <byte> [byte...]\n");
		return -1;
	}
	if (parse_number(argv[0], &offset) < 0)
		return -1;

	buf = malloc((size_t)(argc - 1));
	if (!buf) {
		perror("malloc");
		return -1;
	}

	for (i = 1; i < argc; ++i) {
		if (parse_number(argv[i], &value) < 0) {
			free(buf);
			return -1;
		}
		if (value < 0 || value > 0xff) {
			fprintf(stderr, "byte value out of range: %s\n", argv[i]);
			free(buf);
			return -1;
		}
		buf[i - 1] = (uint8_t)value;
	}

	if (eeprom_write(fd, cfg, offset, buf, argc - 1) < 0) {
		free(buf);
		return -1;
	}

	printf("Wrote %d byte(s) to EEPROM offset 0x%03x\n", argc - 1, offset);
	free(buf);
	return 0;
}

int main(int argc, char **argv)
{
	struct app_config cfg = {
		.bus = EEPROM24C16_DEFAULT_BUS,
		.base_addr = EEPROM24C16_DEFAULT_BASE_ADDR,
	};
	const char *cmd = NULL;
	int cmd_index = -1;
	int fd;
	int rc;
	int i;

	for (i = 1; i < argc; ++i) {
		if (strcmp(argv[i], "--bus") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "--bus requires a value\n");
				return 1;
			}
			if (parse_number(argv[i], &cfg.bus) < 0)
				return 1;
		} else if (strcmp(argv[i], "--base-addr") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "--base-addr requires a value\n");
				return 1;
			}
			if (parse_number(argv[i], &cfg.base_addr) < 0)
				return 1;
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			print_usage(argv[0]);
			return 0;
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "unknown option: %s\n", argv[i]);
			return 1;
		} else {
			cmd = argv[i];
			cmd_index = i;
			break;
		}
	}

	if (!cmd) {
		print_usage(argv[0]);
		return 1;
	}
	if (cfg.base_addr < 0x03 || cfg.base_addr > 0x77) {
		fprintf(stderr, "base address out of 7-bit I2C range: 0x%02x\n",
			cfg.base_addr);
		return 1;
	}
	if (cfg.base_addr + EEPROM24C16_NUM_BLOCKS - 1 > 0x77) {
		fprintf(stderr, "24C16 address window 0x%02x-0x%02x exceeds I2C range\n",
			cfg.base_addr,
			cfg.base_addr + EEPROM24C16_NUM_BLOCKS - 1);
		return 1;
	}

	fd = open_i2c_bus(cfg.bus);
	if (fd < 0)
		return 1;

	if (set_slave_addr(fd, cfg.base_addr) < 0) {
		close(fd);
		return 1;
	}

	if (strcmp(cmd, "read") == 0)
		rc = cmd_read(fd, &cfg, argc - cmd_index - 1, &argv[cmd_index + 1]);
	else if (strcmp(cmd, "write") == 0)
		rc = cmd_write(fd, &cfg, argc - cmd_index - 1, &argv[cmd_index + 1]);
	else if (strcmp(cmd, "dump") == 0)
		rc = cmd_dump(fd, &cfg, argc - cmd_index - 1, &argv[cmd_index + 1]);
	else {
		fprintf(stderr, "unknown command: %s\n", cmd);
		print_usage(argv[0]);
		close(fd);
		return 1;
	}

	close(fd);
	return rc == 0 ? 0 : 1;
}
