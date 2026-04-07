CC ?= cc
CFLAGS ?= -O2

app_demo: src/main.c
	$(CC) $(CFLAGS) -Iinclude -o $@ src/main.c

.PHONY: clean

clean:
	rm -f app_demo
