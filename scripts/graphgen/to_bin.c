#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
	FILE *in_fp = fopen("./mem_init.hex", "r");
	FILE *out_fp = fopen("./graph.bin", "wb");

	uint64_t data[8];
	uint64_t bytes = 0;

	while (fscanf(in_fp, "%16llx%16llx%16llx%16llx%16llx%16llx%16llx%16llx", &data[j], &data[6], &data[5], &data[4], &data[3], &data[2], &data[1], &data[0]) == 8) {
		fwrite(data, 64, 1, out_fp);
		bytes += 64;
	}

	memset(&data, 0, 64);
	while ((bytes % 4096) != 0) {
		fwrite(data, 64, 1, out_fp);
		bytes += 64;
	}

	fclose(out_fp);
	fclose(in_fp);
}
