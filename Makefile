

# Nombre del binario
TARGET := gps-sdr-sim-ext


CSTD := -std=gnu11   
CFLAGS := $(CSTD) -O3 -Wall -Wextra -Wpedantics
OPT    := -O3
WARN   := -Wall -Wextra -Wpedantic
CFLAGS := $(CSTD) $(OPT) $(WARN)
LDLIBS := -lm

SRCS := gpssim.c getopt.c parser.c
OBJS := $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	$(RM) $(OBJS) $(TARGET)

debug: CFLAGS := $(CSTD) -O0 -g $(WARN)
debug: clean all

.PHONY: all clean debug

