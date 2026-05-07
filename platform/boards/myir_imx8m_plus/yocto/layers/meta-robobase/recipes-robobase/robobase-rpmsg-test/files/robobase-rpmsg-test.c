#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <termios.h>
#include <unistd.h>

#include "robobase/rb_safety_proto.h"

#define DEFAULT_DEVICE "/dev/ttyRPMSG30"
#define DEFAULT_TIMEOUT_MS 1000
#define DEFAULT_COUNT 1
#define DEFAULT_LEASE_TIMEOUT_MS 200
#define RPMSG_TTY_PAYLOAD_MAX 496

struct app_options {
	const char *device;
	const char *message;
	int timeout_ms;
	int count;
	int lease_timeout_ms;
	uint32_t clear_mask;
	bool append_newline;
	bool list_devices;
	bool safety_mode;
	bool upstream_lease_valid;
	bool driver_ok;
	bool power_ok;
	bool clear_fault;
};

static long now_ms(void)
{
	struct timeval tv;

	if (gettimeofday(&tv, NULL) < 0)
		return 0;

	return tv.tv_sec * 1000L + tv.tv_usec / 1000L;
}

static const char *safe_state_name(uint8_t state)
{
	switch (state) {
	case RB_SAFE_BOOT:
		return "BOOT";
	case RB_SAFE_STANDBY:
		return "STANDBY";
	case RB_SAFE_ARMED:
		return "ARMED";
	case RB_SAFE_RUNNING:
		return "RUNNING";
	case RB_SAFE_STOP:
		return "SAFE_STOP";
	case RB_SAFE_FAULT_LATCHED:
		return "FAULT_LATCHED";
	default:
		return "UNKNOWN";
	}
}

static void print_usage(const char *prog)
{
	printf("Usage:\n");
	printf("  %s [options]\n", prog);
	printf("\n");
	printf("Basic echo mode options:\n");
	printf("  -d, --device PATH          RPMsg tty device, default %s\n", DEFAULT_DEVICE);
	printf("  -m, --message TEXT         Message to send. Default: robobase-test-N\\n\n");
	printf("  -n, --count N              Number of messages, default %d\n", DEFAULT_COUNT);
	printf("  -t, --timeout-ms N         Timeout per message, default %d\n",
	       DEFAULT_TIMEOUT_MS);
	printf("      --append-newline       Append newline to --message when missing\n");
	printf("\n");
	printf("Safety protocol mode options:\n");
	printf("      --safety               Send RB_SAFE_MSG_LEASE and expect STATUS\n");
	printf("      --lease-timeout-ms N   Lease timeout field, default %d\n",
	       DEFAULT_LEASE_TIMEOUT_MS);
	printf("      --upstream-invalid     Send upstream_lease_valid=0\n");
	printf("      --driver-fault         Send driver_ok=0\n");
	printf("      --power-fault          Send power_ok=0\n");
	printf("      --clear-fault MASK     Send CLEAR_FAULT with mask before lease loop\n");
	printf("\n");
	printf("Other options:\n");
	printf("  -l, --list                 List /dev/*rpmsg* candidates and exit\n");
	printf("  -h, --help                 Show this help\n");
	printf("\n");
	printf("Examples:\n");
	printf("  %s\n", prog);
	printf("  %s --safety -n 10\n", prog);
	printf("  %s --safety --upstream-invalid\n", prog);
	printf("  %s --safety --clear-fault 0xffffffff\n", prog);
}

static int parse_positive_int(const char *text, int *value)
{
	char *end = NULL;
	long parsed;

	errno = 0;
	parsed = strtol(text, &end, 0);
	if (errno || !text[0] || (end && *end) || parsed <= 0 || parsed > 1000000) {
		fprintf(stderr, "invalid positive integer: %s\n", text);
		return -1;
	}

	*value = (int)parsed;
	return 0;
}

static int parse_u32(const char *text, uint32_t *value)
{
	char *end = NULL;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(text, &end, 0);
	if (errno || !text[0] || (end && *end) || parsed > 0xffffffffUL) {
		fprintf(stderr, "invalid u32: %s\n", text);
		return -1;
	}

	*value = (uint32_t)parsed;
	return 0;
}

static int parse_args(int argc, char **argv, struct app_options *opts)
{
	int i;

	opts->device = DEFAULT_DEVICE;
	opts->message = NULL;
	opts->timeout_ms = DEFAULT_TIMEOUT_MS;
	opts->count = DEFAULT_COUNT;
	opts->lease_timeout_ms = DEFAULT_LEASE_TIMEOUT_MS;
	opts->clear_mask = 0;
	opts->append_newline = false;
	opts->list_devices = false;
	opts->safety_mode = false;
	opts->upstream_lease_valid = true;
	opts->driver_ok = true;
	opts->power_ok = true;
	opts->clear_fault = false;

	for (i = 1; i < argc; ++i) {
		if (!strcmp(argv[i], "-d") || !strcmp(argv[i], "--device")) {
			if (++i >= argc) {
				fprintf(stderr, "--device requires a path\n");
				return -1;
			}
			opts->device = argv[i];
		} else if (!strcmp(argv[i], "-m") || !strcmp(argv[i], "--message")) {
			if (++i >= argc) {
				fprintf(stderr, "--message requires text\n");
				return -1;
			}
			opts->message = argv[i];
		} else if (!strcmp(argv[i], "-n") || !strcmp(argv[i], "--count")) {
			if (++i >= argc || parse_positive_int(argv[i], &opts->count) < 0)
				return -1;
		} else if (!strcmp(argv[i], "-t") || !strcmp(argv[i], "--timeout-ms")) {
			if (++i >= argc || parse_positive_int(argv[i], &opts->timeout_ms) < 0)
				return -1;
		} else if (!strcmp(argv[i], "--lease-timeout-ms")) {
			if (++i >= argc || parse_positive_int(argv[i], &opts->lease_timeout_ms) < 0)
				return -1;
		} else if (!strcmp(argv[i], "--append-newline")) {
			opts->append_newline = true;
		} else if (!strcmp(argv[i], "--safety")) {
			opts->safety_mode = true;
		} else if (!strcmp(argv[i], "--upstream-invalid")) {
			opts->safety_mode = true;
			opts->upstream_lease_valid = false;
		} else if (!strcmp(argv[i], "--driver-fault")) {
			opts->safety_mode = true;
			opts->driver_ok = false;
		} else if (!strcmp(argv[i], "--power-fault")) {
			opts->safety_mode = true;
			opts->power_ok = false;
		} else if (!strcmp(argv[i], "--clear-fault")) {
			if (++i >= argc || parse_u32(argv[i], &opts->clear_mask) < 0)
				return -1;
			opts->safety_mode = true;
			opts->clear_fault = true;
		} else if (!strcmp(argv[i], "-l") || !strcmp(argv[i], "--list")) {
			opts->list_devices = true;
		} else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			print_usage(argv[0]);
			exit(0);
		} else {
			fprintf(stderr, "unknown option: %s\n", argv[i]);
			return -1;
		}
	}

	return 0;
}

static void list_pattern(const char *pattern)
{
	glob_t g;
	size_t i;
	int ret;

	ret = glob(pattern, 0, NULL, &g);
	if (ret == GLOB_NOMATCH)
		return;
	if (ret != 0) {
		fprintf(stderr, "glob failed for %s\n", pattern);
		return;
	}

	for (i = 0; i < g.gl_pathc; ++i)
		printf("%s\n", g.gl_pathv[i]);

	globfree(&g);
}

static void list_devices(void)
{
	list_pattern("/dev/ttyRPMSG*");
	list_pattern("/dev/rpmsg*");
}

static int configure_tty_raw(int fd)
{
	struct termios tio;

	if (tcgetattr(fd, &tio) < 0) {
		fprintf(stderr, "warning: tcgetattr failed: %s\n", strerror(errno));
		return 0;
	}

	cfmakeraw(&tio);
	tio.c_cc[VMIN] = 0;
	tio.c_cc[VTIME] = 0;

	if (tcsetattr(fd, TCSANOW, &tio) < 0) {
		fprintf(stderr, "warning: tcsetattr failed: %s\n", strerror(errno));
		return 0;
	}

	if (tcflush(fd, TCIOFLUSH) < 0)
		fprintf(stderr, "warning: tcflush failed: %s\n", strerror(errno));

	return 0;
}

static int write_all(int fd, const unsigned char *buf, size_t len)
{
	size_t written = 0;

	while (written < len) {
		ssize_t ret = write(fd, buf + written, len - written);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "write failed: %s\n", strerror(errno));
			return -1;
		}
		if (ret == 0) {
			fprintf(stderr, "write returned 0\n");
			return -1;
		}
		written += (size_t)ret;
	}

	return 0;
}

static int wait_readable(int fd, int timeout_ms)
{
	struct pollfd pfd;
	int ret;

	pfd.fd = fd;
	pfd.events = POLLIN;
	pfd.revents = 0;

	do {
		ret = poll(&pfd, 1, timeout_ms);
	} while (ret < 0 && errno == EINTR);

	if (ret < 0) {
		fprintf(stderr, "poll failed: %s\n", strerror(errno));
		return -1;
	}
	if (ret == 0)
		return 0;
	if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) {
		fprintf(stderr, "device poll error: revents=0x%x\n", pfd.revents);
		return -1;
	}

	return 1;
}

static int read_exact(int fd, unsigned char *buf, size_t len, int timeout_ms)
{
	size_t got = 0;
	long deadline = now_ms() + timeout_ms;

	while (got < len) {
		long remain = deadline - now_ms();
		ssize_t ret;
		int ready;

		if (remain <= 0) {
			fprintf(stderr, "timeout reading %zu bytes: got %zu\n", len, got);
			return -1;
		}

		ready = wait_readable(fd, (int)remain);
		if (ready <= 0) {
			if (ready == 0)
				continue;
			return -1;
		}

		ret = read(fd, buf + got, len - got);
		if (ret < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			fprintf(stderr, "read failed: %s\n", strerror(errno));
			return -1;
		}
		if (ret == 0)
			continue;
		got += (size_t)ret;
	}

	return 0;
}

static int wait_echo(int fd, const unsigned char *payload, size_t payload_len,
		     int timeout_ms)
{
	unsigned char buf[128];
	size_t matched = 0;
	long deadline = now_ms() + timeout_ms;

	while (matched < payload_len) {
		long remain = deadline - now_ms();
		ssize_t ret;
		size_t i;
		int ready;

		if (remain <= 0) {
			fprintf(stderr, "timeout waiting for echo: matched %zu/%zu bytes\n",
				matched, payload_len);
			return -1;
		}

		ready = wait_readable(fd, (int)remain);
		if (ready <= 0) {
			if (ready == 0)
				continue;
			return -1;
		}

		ret = read(fd, buf, sizeof(buf));
		if (ret < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			fprintf(stderr, "read failed: %s\n", strerror(errno));
			return -1;
		}
		if (ret == 0)
			continue;

		for (i = 0; i < (size_t)ret; ++i) {
			if (matched >= payload_len)
				break;
			if (buf[i] != payload[matched]) {
				fprintf(stderr,
					"echo mismatch at byte %zu: expected 0x%02x got 0x%02x\n",
					matched, payload[matched], buf[i]);
				return -1;
			}
			matched++;
		}
	}

	return 0;
}

static int make_payload(const struct app_options *opts, int index,
			unsigned char *payload, size_t payload_size, size_t *payload_len)
{
	int ret;
	size_t len;

	if (opts->message) {
		len = strlen(opts->message);
		if (len >= payload_size) {
			fprintf(stderr, "message too long\n");
			return -1;
		}
		memcpy(payload, opts->message, len);
		if (opts->append_newline && (len == 0 || payload[len - 1] != '\n')) {
			if (len + 1 >= payload_size) {
				fprintf(stderr, "message too long after newline append\n");
				return -1;
			}
			payload[len++] = '\n';
		}
	} else {
		ret = snprintf((char *)payload, payload_size, "robobase-test-%d\n", index);
		if (ret < 0 || (size_t)ret >= payload_size) {
			fprintf(stderr, "failed to build default payload\n");
			return -1;
		}
		len = (size_t)ret;
	}

	if (len == 0) {
		fprintf(stderr, "empty payload is not useful for echo testing\n");
		return -1;
	}
	if (len > RPMSG_TTY_PAYLOAD_MAX) {
		fprintf(stderr, "payload is %zu bytes, max supported is %d bytes\n",
			len, RPMSG_TTY_PAYLOAD_MAX);
		return -1;
	}

	*payload_len = len;
	return 0;
}

static int read_status_frame(int fd, uint32_t expected_seq, int timeout_ms,
			     struct rb_safe_status_msg *status)
{
	struct rb_safe_hdr hdr;

	if (read_exact(fd, (unsigned char *)&hdr, sizeof(hdr), timeout_ms) < 0)
		return -1;

	if (!rb_safe_hdr_is_valid(&hdr, sizeof(*status)) ||
	    hdr.msg_type != RB_SAFE_MSG_STATUS) {
		fprintf(stderr,
			"invalid safety status header: magic=0x%08x type=%u seq=%u payload=%u\n",
			hdr.magic, hdr.msg_type, hdr.seq, hdr.payload_len);
		return -1;
	}

	if (hdr.seq != expected_seq) {
		fprintf(stderr, "status seq mismatch: expected=%u got=%u\n",
			expected_seq, hdr.seq);
		return -1;
	}

	if (read_exact(fd, (unsigned char *)status, sizeof(*status), timeout_ms) < 0)
		return -1;

	return 0;
}

static void print_status(int index, const struct rb_safe_status_msg *status)
{
	printf("status %d state=%s motion=%u fault=0x%08x latched=0x%08x "
	       "heartbeat=%u last_seq=%u lease_age=%u loop=%u\n",
	       index, safe_state_name(status->state), status->motion_enable,
	       status->fault_bits, status->latched_fault_bits,
	       status->heartbeat_counter, status->last_linux_seq,
	       status->last_lease_age_ms, status->safety_loop_counter);
}

static int send_clear_fault(int fd, uint32_t seq, uint32_t clear_mask, int timeout_ms)
{
	unsigned char frame[sizeof(struct rb_safe_hdr) + sizeof(struct rb_safe_clear_fault_msg)];
	struct rb_safe_hdr *hdr = (struct rb_safe_hdr *)frame;
	struct rb_safe_clear_fault_msg *clear =
		(struct rb_safe_clear_fault_msg *)(frame + sizeof(*hdr));
	struct rb_safe_status_msg status;

	rb_safe_hdr_init(hdr, RB_SAFE_MSG_CLEAR_FAULT, seq, sizeof(*clear));
	clear->request_id = seq;
	clear->clear_mask = clear_mask;
	clear->confirm = RB_SAFE_CLEAR_CONFIRM;

	if (write_all(fd, frame, sizeof(frame)) < 0)
		return -1;
	if (read_status_frame(fd, seq, timeout_ms, &status) < 0)
		return -1;

	print_status(0, &status);
	return 0;
}

static int run_safety_mode(int fd, const struct app_options *opts)
{
	unsigned char frame[sizeof(struct rb_safe_hdr) + sizeof(struct rb_safe_lease_msg)];
	struct rb_safe_hdr *hdr = (struct rb_safe_hdr *)frame;
	struct rb_safe_lease_msg *lease =
		(struct rb_safe_lease_msg *)(frame + sizeof(*hdr));
	long start_ms = now_ms();
	int failures = 0;
	int ok_count = 0;
	int i;
	uint32_t seq = 1;

	if (opts->clear_fault) {
		if (send_clear_fault(fd, seq++, opts->clear_mask, opts->timeout_ms) < 0)
			return 1;
	}

	for (i = 1; i <= opts->count; ++i, ++seq) {
		struct rb_safe_status_msg status;

		rb_safe_hdr_init(hdr, RB_SAFE_MSG_LEASE, seq, sizeof(*lease));
		lease->linux_uptime_ms = (uint32_t)(now_ms() - start_ms);
		lease->lease_timeout_ms = (uint32_t)opts->lease_timeout_ms;
		lease->linux_alive = 1;
		lease->upstream_lease_valid = opts->upstream_lease_valid ? 1 : 0;
		lease->driver_ok = opts->driver_ok ? 1 : 0;
		lease->power_ok = opts->power_ok ? 1 : 0;
		lease->control_seq_seen = seq;
		lease->reserved = 0;

		if (write_all(fd, frame, sizeof(frame)) < 0 ||
		    read_status_frame(fd, seq, opts->timeout_ms, &status) < 0) {
			fprintf(stderr, "safety message %d failed\n", i);
			failures++;
			continue;
		}

		print_status(i, &status);
		ok_count++;
		usleep(20000);
	}

	printf("summary: requested=%d ok=%d failed=%d\n",
	       opts->count, ok_count, failures);

	return failures ? 1 : 0;
}

static int run_echo_mode(int fd, const struct app_options *opts)
{
	unsigned char payload[RPMSG_TTY_PAYLOAD_MAX + 2];
	int failures = 0;
	int ok_count = 0;
	long start_ms = now_ms();
	int i;

	for (i = 1; i <= opts->count; ++i) {
		size_t payload_len;
		long msg_start;

		if (make_payload(opts, i, payload, sizeof(payload), &payload_len) < 0) {
			failures++;
			break;
		}

		msg_start = now_ms();
		if (write_all(fd, payload, payload_len) < 0 ||
		    wait_echo(fd, payload, payload_len, opts->timeout_ms) < 0) {
			fprintf(stderr, "message %d failed\n", i);
			failures++;
			continue;
		}

		printf("ok %d/%d len=%zu rtt=%ld ms\n",
		       i, opts->count, payload_len, now_ms() - msg_start);
		fflush(stdout);
		ok_count++;
	}

	printf("summary: requested=%d ok=%d failed=%d elapsed=%ld ms\n",
	       opts->count, ok_count, failures, now_ms() - start_ms);

	return failures ? 1 : 0;
}

int main(int argc, char **argv)
{
	struct app_options opts;
	int fd;
	int ret;

	if (parse_args(argc, argv, &opts) < 0) {
		print_usage(argv[0]);
		return 2;
	}

	if (opts.list_devices) {
		list_devices();
		return 0;
	}

	fd = open(opts.device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "failed to open %s: %s\n", opts.device, strerror(errno));
		fprintf(stderr, "hint: load imx_rpmsg_tty, start the M7 firmware, then check /dev/ttyRPMSG*\n");
		return 1;
	}

	configure_tty_raw(fd);

	printf("robobase-rpmsg-test\n");
	printf("  device    : %s\n", opts.device);
	printf("  mode      : %s\n", opts.safety_mode ? "safety-v0.1" : "echo");
	printf("  count     : %d\n", opts.count);
	printf("  timeout   : %d ms\n", opts.timeout_ms);
	if (opts.safety_mode)
		printf("  lease     : %d ms\n", opts.lease_timeout_ms);
	fflush(stdout);

	if (opts.safety_mode)
		ret = run_safety_mode(fd, &opts);
	else
		ret = run_echo_mode(fd, &opts);

	close(fd);
	return ret;
}
