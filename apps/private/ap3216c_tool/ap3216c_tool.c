#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

/*
 * This tool is intentionally implemented on top of i2cget/i2cset so it can be
 * used as a learning bridge:
 * 1. First confirm the AP3216C is visible on i2c-0 with i2cdetect.
 * 2. Then use this app to organize the common register accesses into commands.
 * 3. Later, this user-space flow can be rewritten to use /dev/i2c-* ioctls or
 *    moved into a kernel I2C driver.
 */
#define AP3216C_DEFAULT_BUS 0
#define AP3216C_DEFAULT_ADDR 0x1e

/* AP3216C key registers used by this user-space helper. */
#define REG_SYSTEM_CONFIG 0x00
#define REG_INT_STATUS 0x01
#define REG_INT_CLEAR_MANNER 0x02
#define REG_IR_DATA_LOW 0x0a
#define REG_IR_DATA_HIGH 0x0b
#define REG_ALS_DATA_LOW 0x0c
#define REG_ALS_DATA_HIGH 0x0d
#define REG_PS_DATA_LOW 0x0e
#define REG_PS_DATA_HIGH 0x0f
#define REG_ALS_CONFIG 0x10

/* Sensor operating modes from the AP3216C system configuration register. */
enum ap3216c_mode {
	AP3216C_MODE_POWER_DOWN = 0x0,
	AP3216C_MODE_ALS = 0x1,
	AP3216C_MODE_PS_IR = 0x2,
	AP3216C_MODE_ALS_PS_IR = 0x3,
	AP3216C_MODE_SW_RESET = 0x4,
	AP3216C_MODE_ALS_ONCE = 0x5,
	AP3216C_MODE_PS_IR_ONCE = 0x6,
	AP3216C_MODE_ALS_PS_IR_ONCE = 0x7,
};

/* Runtime configuration parsed from the command line. */
struct app_config {
	int bus;
	int addr;
};

static void print_usage(const char *prog)
{
	printf("Usage:\n");
	printf("  %s [--bus N] [--addr 0x1e] <command>\n", prog);
	printf("\n");
	printf("Commands:\n");
	printf("  status        Show system/int/ALS config registers\n");
	printf("  init          Enable ALS + PS + IR continuous mode\n");
	printf("  reset         Software reset\n");
	printf("  powerdown     Enter power-down mode\n");
	printf("  read-als      Read ALS raw value and lux estimate\n");
	printf("  read-ps       Read PS raw value and object status\n");
	printf("  read-ir       Read IR raw value\n");
	printf("  dump          Dump key AP3216C registers\n");
	printf("\n");
	printf("Examples:\n");
	printf("  %s status\n", prog);
	printf("  %s init\n", prog);
	printf("  %s read-als\n", prog);
}

/*
 * Wrap a shell command and optionally capture the first output line.
 *
 * The goal here is not performance. The goal is to reuse the already validated
 * i2c-tools behavior while keeping the AP3216C access flow readable.
 */
static int run_shell_command(const char *cmd, char *buf, size_t buf_size)
{
	FILE *fp;
	int status;

	fp = popen(cmd, "r");
	if (!fp) {
		perror("popen");
		return -1;
	}

	if (buf && buf_size > 0) {
		if (!fgets(buf, (int)buf_size, fp)) {
			buf[0] = '\0';
		}
	}

	status = pclose(fp);
	if (status == -1) {
		perror("pclose");
		return -1;
	}

	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		fprintf(stderr, "command failed: %s\n", cmd);
		return -1;
	}

	return 0;
}

/* Read one 8-bit AP3216C register through i2cget. */
static int ap3216c_read_reg(const struct app_config *cfg, int reg, int *value)
{
	char cmd[128];
	char out[64];
	char *end;
	long parsed;

	snprintf(cmd, sizeof(cmd),
		 "i2cget -y %d 0x%02x 0x%02x",
		 cfg->bus, cfg->addr, reg);
	if (run_shell_command(cmd, out, sizeof(out)) < 0)
		return -1;

	parsed = strtol(out, &end, 0);
	if (end == out) {
		fprintf(stderr, "failed to parse i2cget output: %s\n", out);
		return -1;
	}

	*value = (int)parsed;
	return 0;
}

/* Write one 8-bit AP3216C register through i2cset. */
static int ap3216c_write_reg(const struct app_config *cfg, int reg, int value)
{
	char cmd[128];

	snprintf(cmd, sizeof(cmd),
		 "i2cset -y %d 0x%02x 0x%02x 0x%02x",
		 cfg->bus, cfg->addr, reg, value & 0xff);
	return run_shell_command(cmd, NULL, 0);
}

/* Read a little-endian 16-bit value split across low/high registers. */
static int ap3216c_read_u16(const struct app_config *cfg, int low_reg, int high_reg, int *value)
{
	int low;
	int high;

	if (ap3216c_read_reg(cfg, low_reg, &low) < 0)
		return -1;
	if (ap3216c_read_reg(cfg, high_reg, &high) < 0)
		return -1;

	*value = ((high & 0xff) << 8) | (low & 0xff);
	return 0;
}

/*
 * ALS resolution depends on gain bits in REG_ALS_CONFIG.
 * This converts the raw ALS code to an approximate lux value.
 */
static double ap3216c_als_resolution(int als_cfg)
{
	switch ((als_cfg >> 4) & 0x3) {
	case 0x0:
		return 0.35;
	case 0x1:
		return 0.0788;
	case 0x2:
		return 0.0197;
	case 0x3:
		return 0.0049;
	default:
		return 0.35;
	}
}

/* Print a few core registers so bring-up can start from a known state. */
static int cmd_status(const struct app_config *cfg)
{
	int sys_cfg;
	int int_status;
	int als_cfg;

	if (ap3216c_read_reg(cfg, REG_SYSTEM_CONFIG, &sys_cfg) < 0)
		return -1;
	if (ap3216c_read_reg(cfg, REG_INT_STATUS, &int_status) < 0)
		return -1;
	if (ap3216c_read_reg(cfg, REG_ALS_CONFIG, &als_cfg) < 0)
		return -1;

	printf("AP3216C status\n");
	printf("  bus             : i2c-%d\n", cfg->bus);
	printf("  address         : 0x%02x\n", cfg->addr);
	printf("  system_config   : 0x%02x\n", sys_cfg);
	printf("  mode            : 0x%x\n", sys_cfg & 0x7);
	printf("  int_status      : 0x%02x\n", int_status);
	printf("  als_config      : 0x%02x\n", als_cfg);
	printf("  als_gain_bits   : 0x%x\n", (als_cfg >> 4) & 0x3);

	return 0;
}

/* Put the sensor into the most useful continuous-measurement mode. */
static int cmd_init(const struct app_config *cfg)
{
	if (ap3216c_write_reg(cfg, REG_SYSTEM_CONFIG, AP3216C_MODE_ALS_PS_IR) < 0)
		return -1;

	printf("AP3216C set to ALS + PS + IR continuous mode (0x03)\n");
	return 0;
}

/* Trigger a software reset through REG_SYSTEM_CONFIG. */
static int cmd_reset(const struct app_config *cfg)
{
	if (ap3216c_write_reg(cfg, REG_SYSTEM_CONFIG, AP3216C_MODE_SW_RESET) < 0)
		return -1;

	printf("AP3216C software reset issued (0x04)\n");
	return 0;
}

/* Stop conversions so the chip stays in low-power mode. */
static int cmd_powerdown(const struct app_config *cfg)
{
	if (ap3216c_write_reg(cfg, REG_SYSTEM_CONFIG, AP3216C_MODE_POWER_DOWN) < 0)
		return -1;

	printf("AP3216C entered power-down mode (0x00)\n");
	return 0;
}

/* Read ALS result and convert it to a user-friendly lux estimate. */
static int cmd_read_als(const struct app_config *cfg)
{
	int als_cfg;
	int als_raw;
	double lux;

	if (ap3216c_read_reg(cfg, REG_ALS_CONFIG, &als_cfg) < 0)
		return -1;
	if (ap3216c_read_u16(cfg, REG_ALS_DATA_LOW, REG_ALS_DATA_HIGH, &als_raw) < 0)
		return -1;

	lux = als_raw * ap3216c_als_resolution(als_cfg);
	printf("ALS raw : %d (0x%04x)\n", als_raw, als_raw & 0xffff);
	printf("ALS lux : %.2f\n", lux);

	return 0;
}

/* Read the raw IR channel, useful for understanding PS/IR behavior. */
static int cmd_read_ir(const struct app_config *cfg)
{
	int ir_raw;

	if (ap3216c_read_u16(cfg, REG_IR_DATA_LOW, REG_IR_DATA_HIGH, &ir_raw) < 0)
		return -1;

	printf("IR raw  : %d (0x%04x)\n", ir_raw, ir_raw & 0xffff);
	return 0;
}

/*
 * PS data uses status bits and payload bits mixed across the two registers.
 * This helper splits them into:
 * - object detected flag
 * - IR overflow flag
 * - 10-bit raw proximity code
 */
static int cmd_read_ps(const struct app_config *cfg)
{
	int low;
	int high;
	int raw;
	int obj;
	int ir_of;

	if (ap3216c_read_reg(cfg, REG_PS_DATA_LOW, &low) < 0)
		return -1;
	if (ap3216c_read_reg(cfg, REG_PS_DATA_HIGH, &high) < 0)
		return -1;

	obj = (high >> 7) & 0x1;
	ir_of = (high >> 6) & 0x1;
	raw = ((high & 0x3f) << 4) | (low & 0x0f);

	printf("PS raw          : %d (0x%03x)\n", raw, raw & 0x3ff);
	printf("Object detected : %s\n", obj ? "yes" : "no");
	printf("IR overflow     : %s\n", ir_of ? "yes" : "no");

	return 0;
}

/* Dump a compact set of registers for quick debugging and bring-up logs. */
static int cmd_dump(const struct app_config *cfg)
{
	static const int regs[] = {
		REG_SYSTEM_CONFIG,
		REG_INT_STATUS,
		REG_INT_CLEAR_MANNER,
		REG_IR_DATA_LOW,
		REG_IR_DATA_HIGH,
		REG_ALS_DATA_LOW,
		REG_ALS_DATA_HIGH,
		REG_PS_DATA_LOW,
		REG_PS_DATA_HIGH,
		REG_ALS_CONFIG,
	};
	size_t i;
	int value;

	for (i = 0; i < sizeof(regs) / sizeof(regs[0]); ++i) {
		if (ap3216c_read_reg(cfg, regs[i], &value) < 0)
			return -1;
		printf("reg[0x%02x] = 0x%02x\n", regs[i], value & 0xff);
	}

	return 0;
}

int main(int argc, char **argv)
{
	/* Default to the board's AP3216C wiring on i2c-0 @ 0x1e. */
	struct app_config cfg = {
		.bus = AP3216C_DEFAULT_BUS,
		.addr = AP3216C_DEFAULT_ADDR,
	};
	const char *cmd = NULL;
	int i;

	for (i = 1; i < argc; ++i) {
		if (strcmp(argv[i], "--bus") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "--bus requires a value\n");
				return 1;
			}
			cfg.bus = atoi(argv[i]);
		} else if (strcmp(argv[i], "--addr") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "--addr requires a value\n");
				return 1;
			}
			cfg.addr = (int)strtol(argv[i], NULL, 0);
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			print_usage(argv[0]);
			return 0;
		} else if (argv[i][0] == '-') {
			fprintf(stderr, "unknown option: %s\n", argv[i]);
			return 1;
		} else {
			cmd = argv[i];
			break;
		}
	}

	if (!cmd) {
		print_usage(argv[0]);
		return 1;
	}

	/* Keep the dispatch flat so each subcommand maps to one hardware action. */
	if (strcmp(cmd, "status") == 0)
		return cmd_status(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "init") == 0)
		return cmd_init(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "reset") == 0)
		return cmd_reset(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "powerdown") == 0)
		return cmd_powerdown(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "read-als") == 0)
		return cmd_read_als(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "read-ps") == 0)
		return cmd_read_ps(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "read-ir") == 0)
		return cmd_read_ir(&cfg) == 0 ? 0 : 1;
	if (strcmp(cmd, "dump") == 0)
		return cmd_dump(&cfg) == 0 ? 0 : 1;

	fprintf(stderr, "unknown command: %s\n", cmd);
	print_usage(argv[0]);
	return 1;
}
