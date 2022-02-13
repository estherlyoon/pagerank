#!/bin/bash
 
SYS="${1:-1}"
CYT="${2:-1}"
PHYS="${3:-1}"

datasets=("small" "med" "large")

# System
if [[ "$SYS" -eq 1 ]]; then
	for i in ${!datasets[@]}; do
		# Cold CPU (-c True)
		sudo ./run.py -f data/${datasets[$i]}.bin -cp True -c True -i 4 -t 0 -r 3
		# Warm CPU (warm from copying files into NVME)
		sudo ./run.py -f data/${datasets[$i]}.bin -cp True -i 4 -t 0 -r 3
		sync && sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
		sleep 120
	done
fi

# Physical (-t 2)
if [[ "$PHYS" -eq 1 ]]; then
	# don't get physical data for large
	for i in 0; do
		sudo ./run.py -f data/${datasets[$i]}.bin -cp True -i 4 -t 2 -r 2
		sync && sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
		sleep 120
	done
fi

# Coyote, small pages (-t 1), large pages (-t 3), and custom (-t 4)
if [[ "$CYT" -eq 1 ]]; then
	# 4K and 2M pages, don't get data for large
	for i in 0 1; do
		for t in 1 3; do
			# Cold CPU
			sudo ./run.py -f data/${datasets[$i]}.bin -cp True -c True -i 4 -t $t -r 3
			# Warm CPU
			sudo ./run.py -f data/${datasets[$i]}.bin -cp True -i 4 -t $t -r 3
			sync && sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
			sleep 120
		done
	done
	# Custom
	for i in ${!datasets[@]}; do
		sudo ./run.py -f data/${datasets[$i]}.bin -cp True -c True -i 4 -t 4 -r 3
		sudo ./run.py -f data/${datasets[$i]}.bin -cp True -i 4 -t 4 -r 3
		sync && sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
		sleep 120
	done
fi
