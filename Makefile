
SRC_DIR := src
BIN_DIR := ../bin

EXEC := ${BIN_DIR}/page_rank
DVFILES := $(wildcard $(SRC_DIR)/*.v)
VFILES := $(notdir ${DVFILES})

.PHONY: all clean

all: ${EXEC}

${EXEC}: ${DVFILES} ${BIN_DIR}
	cd src && iverilog -o $@ ${VFILES} && cd -

${BIN_DIR}:
	mkdir -p $@

clean:
	rm -rf ${BIN_DIR}
