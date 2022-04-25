FILE := *.txt

# Find the target file.
override target := $(wildcard $(FILE))
$(if $(filter 0,$(words $(target))),$(error Can't find the target file '$(FILE)'))
$(if $(filter-out 1,$(words $(target))),$(error More than one file matches pattern '$(FILE)'))


# Constants.
override space := $(strip) $(strip)
override hash := \#
override define lf :=
$(strip)
$(strip)
endef

# Used to create local variables in a safer way. E.g. `$(call var,x := 42)`.
override var = $(eval override $(subst $,$$$$,$1))

ifeq ($(filter --trace,$(MAKEFLAGS)),)
# Same as `$(shell ...)`, but triggers a error on failure.
override safe_shell = $(shell $1)$(if $(filter-out 0,$(.SHELLSTATUS)),$(error Unable to execute `$1`, exit code $(.SHELLSTATUS)))
# Same as `$(shell ...)`, expands to the shell status code rather than the command output.
override shell_status = $(call,$(shell $1))$(.SHELLSTATUS)
else
# Same functions but with logging.
override safe_shell = $(info Shell command: $1)$(shell $1)$(if $(filter-out 0,$(.SHELLSTATUS)),$(error Unable to execute `$1`, exit code $(.SHELLSTATUS)))
override shell_status = $(info Shell command: $1)$(call,$(shell $1))$(.SHELLSTATUS)$(info Exit code: $(.SHELLSTATUS))
endif

# Same as `safe_shell`, but discards the output and expands to nothing.
override safe_shell_exec = $(call,$(call safe_shell,$1))

# Encloses $1 in single quotes, with proper escaping for the shell.
override quote = '$(subst ','"'"',$1)'

# Expands to special characters that change text color.
# $1 is the color code, one of:
#     0              1     2       3      4      5      6          7
#   black     DARK( red  green  yellow  blue  purple  cyan )  light-gray
#     8              9    10      11     12     13     14         15
# dark-gray  LIGHT( red  green  yellow  blue  purple  cyan )     white
override color = $(if $(__color_cached$(strip $1)),,$(call var,__color_cached$(strip $1) := $(call safe_shell,tput setaf $1)))$(__color_cached$(strip $1))
# Expands to special characters that reset text color.
override reset_color = $(if $(__color_cached_r),,$(call var,__color_cached_r := $(call safe_shell,tput sgr0)))$(__color_cached_r)
c := # Force colored output
ifeq ($(and $(MAKE_TERMOUT),$(MAKE_TERMERR))$c,)
override color :=
override reset_color :=
endif

# Encloses $1 in double quotes, with proper escaping for AWK.
override awk_quote = "$(subst ",\",$(subst \,\\,$1))"

# Encloses $1 in slashes, with proper escaping (hopefully) for AWK.
override awk_regex = /$(subst /,\/,$1)/

# Expands to an `awk` call. `$1` is the command.
override awk_command = @awk $(call quote,$1) $(call quote,$(target))

# Performs some basic initialization in an AWK program.
override awk_cmd_init = BEGIN {RS = ""; FS = "\n"; item_index = 0; $1}

# If not empty, always print entry bodies.
override force_full :=

# A condition for the entries.
override entry_cond :=

# Search for a specific entry index.
n :=
ifneq ($n,)
override force_full := 1
override entry_cond += && item_index == $n
endif

# Search for a tag.
# Accepts a space-separated list of regexes, each of which is implicitly wrapped in brackes.
# Entries are only accepted if their tag lists match all of the regexes.
t :=
ifneq ($(t),)
override entry_cond += $(foreach x,$(t),&& $$1 ~ $(call awk_regex,\[$x\]))
endif

# Search in the header (title).
h :=
ifneq ($(h),)
override entry_cond += && $$2 ~ $(call awk_regex,$(h))
endif

# Search in the body.
b :=
ifneq ($(b),)
override entry_cond += && body ~ $(call awk_regex,$(b))
endif

# A list of dummy targets, serving as flags for the `do` target.
.PHONY: f # Print full entries instead of just titles.
f: do

# The main target.
.DEFAULT_GOAL := do
.PHONY: do
do:
	$(call awk_command,\
		BEGIN {RS = ""; FS = "\n"; IGNORECASE = 1; item_index = 0}\
		$(call,Skip comment paragraphs starting with the hash symbol, and usage hints starting with the question mark.)\
		$$0 ~ /^[#?]/ {next}\
		$(call,Create a variable 'body' to store the full body of the entry.)\
		{body = $$3; for (i = 4; i <= NF; i++) body = body "\n" $$i}\
		++item_index $(entry_cond) {\
			$(call,Pretty-format the list of tags, by removing any leading/trailing spaces, and spaces between tags.)\
			gsub(/^\s*\[/, "[", $$1); gsub(/\]\s*$$/, "]", $$1); gsub(/\]\s*\[/, "] [", $$1);\
			$(call,Add color to the tags.)\
			$$1 = "$(call color,12)" $$1 "$(reset_color)";\
			$(call,Highlight important tags starting with `-` with a different color.)\
			gsub(/\[\-[^]]*\]/, "$(call color,13)&$(call color,12)", $$1);\
			$(call,Print the list of tags, the index, and the first line.)\
			print $$1 "\n$(call color,1)$(hash)$(call color,9)" item_index "$(call color,15) " $$2 "$(reset_color)";\
			$(if $(force_full)$(filter f,$(MAKECMDGOALS)),print "$(call color,7)" body "$(reset_color)";)\
			print "";\
		}\
	)
	$(call,If we have no custom flags, remind the user about `make help`.)
	$(if $(MAKECMDGOALS)$(MAKEOVERRIDES),,@echo >&2 $(call quote,$(call color,8)Run 'make help' to show usage info.$(reset_color)))
	@true

# The help target.
.PHONY: help
help:
	$(info $(call color,15)Flags:$(reset_color))
	$(info $(space)   $(call color,10)f       $(reset_color)Print entries in full, instead of just titles.)
	$(info $(space)   $(call color,10)t$(call color,12)=...   $(reset_color)Print entries that have the specified [t]ags.)
	$(info $(space)           The parameter is treated as a space-separated list of regexes, each one is implicitly wrapped in brackets.)
	$(info $(space)           Entries are only printed if their tag lists match all of the provided regexes.)
	$(info $(space)           Important tags tend to start with '-'.)
	$(info $(space)   $(call color,10)n$(call color,12)=...   $(reset_color)Print the entry with the specified index. Implies 'f'.)
	$(info $(space)   $(call color,10)h$(call color,12)=...   $(reset_color)Print entries with [h]eaders matching the regex.)
	$(info $(space)   $(call color,10)b$(call color,12)=...   $(reset_color)Print entries with [b]odies matching the regex.)
	$(info $(call color,15)Actions:$(reset_color))
	$(info $(space)   $(call color,10)tags    $(reset_color)List all tags. Add $(call color,12)| fmt$(reset_color) to remove line-breaks.)
	$(info $(space)   $(call color,10)c=1     $(reset_color)Force colored output even when not printing to a terminal.)
	$(info $(space)           `less` likes to automatically remove color, use `less -R` to preserve it.)
	$(call awk_command,\
		BEGIN {first = 1}\
		/^?/ {\
			if (first) {first=0; print "$(call color,15)Extra information provided in '$(target)':$(call color,8)"}\
			print gensub(/^\?\s?/, "", "g", $$0);\
		}\
		END {\
			print "$(reset_color)";\
		}\
	)
	@true

# The target printing a list of all tags.
.PHONY: tags
tags:
	$(call,Note that we're sorting twice. First time to make `uniq` work properly, and the second time to sort by the number of uses.)
	$(call awk_command,BEGIN {RS = ""; FS = "\n"} /^[#?]/ {next} {print $$1}) | tr '\[\]' '\n' | grep -v '^\s*$$' | LC_ALL=C sort | uniq -c | LC_ALL=C sort -r
	@true
