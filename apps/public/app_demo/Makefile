APP_NAME ?= app_demo
CROSS_COMPILE ?=
ifeq ($(origin CC), default)
CC := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)gcc,cc)
endif
ifeq ($(origin CC), undefined)
CC := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)gcc,cc)
endif
ifeq ($(origin STRIP), default)
STRIP := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)strip,strip)
endif
ifeq ($(origin STRIP), undefined)
STRIP := $(if $(CROSS_COMPILE),$(CROSS_COMPILE)strip,strip)
endif
CPPFLAGS ?=
CFLAGS ?= -O2
LDFLAGS ?=
LDLIBS ?=

SRCS := src/main.c
OBJS := $(SRCS:.c=.o)

.PHONY: all clean

all: $(APP_NAME)

$(APP_NAME): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

src/%.o: src/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -Iinclude -c -o $@ $<

clean:
	rm -f $(APP_NAME) $(OBJS)
