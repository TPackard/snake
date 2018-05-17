AS := nasm
LD := ld

LIBRARIES := -lc -lncursesw
LD_SO := /lib64/ld-linux-x86-64.so.2
LDFLAGS := --dynamic-linker $(LD_SO) $(LIBRARIES)

SRC_DIR := src
OBJ_DIR := obj
SRCS := $(wildcard $(SRC_DIR)/*.asm)
OBJS := $(SRCS:$(SRC_DIR)/%.asm=$(OBJ_DIR)/%.o)

OUT := snake
FORMAT := elf64
.PHONY: all

all: $(OBJ_DIR) $(OBJS)
	$(LD) $(LDFLAGS) -o $(OUT) $(OBJS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.asm
	$(AS) -O0 -f $(FORMAT) $< -o $@

$(OBJ_DIR):
	mkdir $(OBJ_DIR)

run: all
	./$(OUT)

scratch: $(OBJ_DIR)
	nasm -f $(FORMAT) test/scratch.asm -o $(OBJ_DIR)/test/scratch.o
	$(LD) $(LDFLAGS) -o test/scratch $(OBJS)
	chmod +x test/scratch
	./test/scratch

clean:
	rm -f $(OUT)
	rm -rf $(OBJ_DIR)
