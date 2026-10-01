SWIFTC = xcrun swiftc
CLANG = xcrun clang
BUILD = .build

.PHONY: all test clean

all: $(BUILD)/editmode-native

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/native_export.o: native_export.m | $(BUILD)
	$(CLANG) -fobjc-arc -Wall -Wextra -Werror -O2 -c $< -o $@

$(BUILD)/edit_mode.o: edit_mode.S | $(BUILD)
	$(CLANG) -c $< -o $@

$(BUILD)/editmode-native: native_export.swift $(BUILD)/native_export.o $(BUILD)/edit_mode.o
	$(SWIFTC) -O -F /System/Library/PrivateFrameworks -framework Foundation \
		-framework WorkflowKit -framework ShortcutsAgent -framework ShortcutsLanguage \
		native_export.swift $(BUILD)/native_export.o $(BUILD)/edit_mode.o -o $@

test: all
	python3 -m unittest discover -s tests -v

clean:
	rm -rf $(BUILD)
