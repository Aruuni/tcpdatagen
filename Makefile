BIN := bin
TARGETS := $(BIN)/sage $(BIN)/athena $(BIN)/client

CXX := g++
CC  := gcc

CXXFLAGS := -pthread -O2 -Wall -Wextra -std=c++17
CFLAGS   := -O2 -Wall -Wextra

.PHONY: all clean distclean

all: $(TARGETS)

# Ensure bin/ exists once before building binaries
$(BIN):
	mkdir -p $(BIN)

$(BIN)/sage: src/sage_dataset.cc src/flow.cc | $(BIN)
	$(CXX) $(CXXFLAGS) $^ -o $@

$(BIN)/athena: src/athena.cc src/flow.cc | $(BIN)
	$(CXX) $(CXXFLAGS) $^ -o $@

$(BIN)/client: src/client.c | $(BIN)
	$(CC) $(CFLAGS) $^ -o $@

clean:
	rm -f $(TARGETS)

distclean: clean
	rm -rf $(BIN)