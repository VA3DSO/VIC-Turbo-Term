# Tools
CA65 = ca65
CC65 = cl65
LD65 = ld65

# Flags
FLAGS = -t vic20
CONFIG = -C vtt.cfg

# Default Target
all: vtt.prg
	# c1541 vtt.d64 < inst.txt
	c1541 ~/Sync/Computers/Commodore/Disks/VIC-20.d64 < inst.txt

# Assemble Source into Objects
vtt.o: vtt.s
	$(CA65) $(FLAGS) vtt.s -o vtt.o

# Link Objects into Executables
vtt.prg: vtt.o
	$(LD65) $(CONFIG) vtt.o -o vtt.prg

# Clean Build Artifacts
clean:
	rm -f *.o *.prg
