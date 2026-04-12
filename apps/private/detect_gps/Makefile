APP_NAME ?= detect_gps
CROSS_COMPILE ?=
ifeq ($(origin CC), default)
CC := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)gcc,cc)
endif
ifeq ($(origin CC), undefined)
CC := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)gcc,cc)
endif
CPPFLAGS ?=
CFLAGS ?= -O2
LDFLAGS ?=
LDLIBS ?=

SRCS := gps_read.c
OBJS := $(SRCS:.c=.o)

.PHONY: all clean

all: $(APP_NAME)

$(APP_NAME): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(APP_NAME) $(OBJS)
