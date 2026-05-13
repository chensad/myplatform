#ifndef ROBOBASE_RB_SAFETY_PROTO_H
#define ROBOBASE_RB_SAFETY_PROTO_H

#include <stdint.h>

#if defined(__GNUC__)
#define RB_SAFE_PACKED __attribute__((packed))
#else
#define RB_SAFE_PACKED
#endif

#define RB_SAFE_MAGIC 0x31534652u /* "RFS1" little-endian */
#define RB_SAFE_VER_MAJOR 0u
#define RB_SAFE_VER_MINOR 1u
#define RB_SAFE_CRC_DISABLED 0u
#define RB_SAFE_CLEAR_CONFIRM 0x514C5243u /* "CRLQ" little-endian */

enum rb_safe_msg_type {
	RB_SAFE_MSG_HELLO = 1,
	RB_SAFE_MSG_LEASE = 2,
	RB_SAFE_MSG_STATUS = 3,
	RB_SAFE_MSG_CLEAR_FAULT = 4,
	RB_SAFE_MSG_DEBUG_INPUTS = 5,
};

enum rb_safe_state {
	RB_SAFE_BOOT = 0,
	RB_SAFE_STANDBY = 1,
	RB_SAFE_ARMED = 2,
	RB_SAFE_RUNNING = 3,
	RB_SAFE_STOP = 4,
	RB_SAFE_FAULT_LATCHED = 5,
};

enum rb_safe_fault_bits {
	RB_FAULT_ESTOP = 1u << 0,
	RB_FAULT_BUMPER = 1u << 1,
	RB_FAULT_LINUX_TIMEOUT = 1u << 2,
	RB_FAULT_UPSTREAM_TIMEOUT = 1u << 3,
	RB_FAULT_DRIVER_FAULT = 1u << 4,
	RB_FAULT_POWER_FAULT = 1u << 5,
	RB_FAULT_PROTOCOL_ERROR = 1u << 6,
};

struct rb_safe_hdr {
	uint32_t magic;
	uint8_t ver_major;
	uint8_t ver_minor;
	uint16_t msg_type;
	uint16_t hdr_len;
	uint16_t payload_len;
	uint32_t seq;
	uint32_t crc32;
} RB_SAFE_PACKED;

struct rb_safe_lease_msg {
	uint32_t linux_uptime_ms;
	uint32_t lease_timeout_ms;
	uint8_t linux_alive;
	uint8_t upstream_lease_valid;
	uint8_t driver_ok;
	uint8_t power_ok;
	uint32_t control_seq_seen;
	uint32_t reserved;
} RB_SAFE_PACKED;

struct rb_safe_status_msg {
	uint32_t m7_uptime_ms;
	uint32_t heartbeat_counter;
	uint8_t state;
	uint8_t motion_enable;
	uint8_t estop_nc_closed;
	uint8_t bumper_nc_closed;
	uint32_t fault_bits;
	uint32_t latched_fault_bits;
	uint32_t last_linux_seq;
	uint32_t last_lease_age_ms;
	uint32_t safety_loop_counter;
	uint32_t reserved;
} RB_SAFE_PACKED;

struct rb_safe_clear_fault_msg {
	uint32_t request_id;
	uint32_t clear_mask;
	uint32_t confirm;
} RB_SAFE_PACKED;

enum rb_safe_debug_input_mask {
	RB_SAFE_DEBUG_INPUT_ESTOP = 1u << 0,
	RB_SAFE_DEBUG_INPUT_BUMPER = 1u << 1,
};

/*
 * Debug-only GPIO input bias control for bench validation without external
 * switches. M7 keeps the pins as real GPIO inputs and applies internal pad bias:
 * 0 = pull-down, emulating NC contact closed to GND; 1 = pull-up, emulating
 * contact open/fault. STATUS still reports the actual GPIO pad sample.
 */
struct rb_safe_debug_inputs_msg {
	uint32_t request_id;
	uint32_t valid_mask;
	uint8_t estop_gpio_level;
	uint8_t bumper_gpio_level;
	uint16_t reserved0;
	uint32_t reserved1;
} RB_SAFE_PACKED;

static inline void rb_safe_hdr_init(struct rb_safe_hdr *hdr, uint16_t msg_type,
				    uint32_t seq, uint16_t payload_len)
{
	hdr->magic = RB_SAFE_MAGIC;
	hdr->ver_major = RB_SAFE_VER_MAJOR;
	hdr->ver_minor = RB_SAFE_VER_MINOR;
	hdr->msg_type = msg_type;
	hdr->hdr_len = (uint16_t)sizeof(*hdr);
	hdr->payload_len = payload_len;
	hdr->seq = seq;
	hdr->crc32 = RB_SAFE_CRC_DISABLED;
}

static inline int rb_safe_hdr_is_valid(const struct rb_safe_hdr *hdr,
				       uint16_t expected_payload_len)
{
	return hdr->magic == RB_SAFE_MAGIC &&
	       hdr->ver_major == RB_SAFE_VER_MAJOR &&
	       hdr->hdr_len == sizeof(*hdr) &&
	       hdr->payload_len == expected_payload_len &&
	       hdr->crc32 == RB_SAFE_CRC_DISABLED;
}

#endif /* ROBOBASE_RB_SAFETY_PROTO_H */
