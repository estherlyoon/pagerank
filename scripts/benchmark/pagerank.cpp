#include <chrono>
#include <stdlib.h>
#include "aos.hpp"

using namespace std::chrono;

struct test_config {
    uint64_t n_vert;
    uint64_t n_inedges;
    uint64_t vaddr;
    uint64_t ieaddr;
    uint64_t waddr0;
    uint64_t waddr1;
    uint64_t rounds;
} test_config;
 
int main(int argc, char *argv[]) {

	char* str_end;
	uint64_t n_vert = strtoull(argv[1], &str_end, 10);
	uint64_t n_ie = strtoull(argv[2], &str_end, 10);
	uint64_t ie_addr = strtoull(argv[3], &str_end, 10);
	uint64_t waddr0 = strtoull(argv[4], &str_end, 10);
	uint64_t waddr1 = strtoull(argv[5], &str_end, 10);
	uint64_t rounds = strtoull(argv[6], &str_end, 10);
	uint64_t num_apps = strtoull(argv[7], &str_end, 10);
	uint64_t mode = strtoull(argv[8], &str_end, 10);
	uint64_t coyote_config = mode == 3 ? 1 : 
							 mode == 4 ? 2 : 0;
	mode = (mode == 3 || mode == 4) ? 1 : mode;

	printf("n_vert = %lu\n", n_vert);
	printf("n_ie = %lu\n", n_ie);
	printf("ie_addr = %lu\n", ie_addr);
	printf("waddr0 = %lu\n", waddr0);
	printf("waddr1 = %lu\n", waddr1);
	printf("rounds = %lu\n", rounds);
	printf("num_apps = %lu\n", num_apps);
	printf("mode = %lu\n", mode);
	printf("coyote_config = %lu\n", coyote_config);

	test_config.n_vert = n_vert;
    test_config.n_inedges = n_ie;
    test_config.vaddr = 0;
    test_config.ieaddr = ie_addr;
    test_config.waddr0 = waddr0;
    test_config.waddr1 = waddr1;
    test_config.rounds = rounds;

	high_resolution_clock::time_point start, first, second, third, end;
	duration<double> diff, init_diff, first_diff, second_diff;
	double init_seconds, round1_seconds, round2_seconds, seconds;
	
	aos_client *aos[4];
	for (uint64_t app = 0; app < num_apps; ++app) {
		aos[app] = new aos_client();
		aos[app]->set_slot_id(0);
		aos[app]->set_app_id(app);
		aos[app]->connect();
		aos[app]->aos_set_mode(mode, coyote_config);
	}
	
	int fd[4];
	const char *fnames[4] = {"/mnt/nvme0/file0.bin", "/mnt/nvme0/file1.bin",
	                         "/mnt/nvme0/file3.bin", "/mnt/nvme0/file2.bin"};
	for (uint64_t app = 0; app < num_apps; ++app) {
		aos[app]->aos_file_open(fnames[app], fd[app]);
		//aos[app]->aos_file_open("/mnt/tmpfs/file0.bin", fd[app]);
		printf("App %lu opened file %d\n", app, fd[app]);
	}
	
	void *addr[4];
	uint64_t filesz = waddr1 + n_vert * 8; // streaming vert + streaming ie + random ie 
	uint64_t length = filesz % 4096 ? filesz + (4096 - (filesz % 4096)) : filesz;
	printf("mapping 0x%lx bytes per file\n", length);
	for (uint64_t app = 0; app < num_apps; ++app) {
		addr[app] = nullptr;
		int prot = 0;
		prot |= PROT_READ;
		prot |= PROT_WRITE;
		
		start = high_resolution_clock::now();
		aos[app]->aos_mmap(addr[app], length, prot, 0, fd[app], 0);
		end = high_resolution_clock::now();
		diff = end - start;
		seconds = diff.count();
		printf("App %lu mmapped file %d at %p in %gs\n", app, fd[app], addr[app], seconds);
	}
	
	for (int i = 0; i < 1; ++i) {
		// start runs
		start = high_resolution_clock::now();
		for (uint64_t app = 0; app < num_apps; ++app) {
			// set test_config values
			uint64_t offset = (uint64_t)addr[app];
			aos[app]->aos_cntrlreg_write(0x0, test_config.n_vert);
			aos[app]->aos_cntrlreg_write(0x8, test_config.n_inedges);
			aos[app]->aos_cntrlreg_write(0x10, offset + test_config.vaddr);
			aos[app]->aos_cntrlreg_write(0x18, offset + test_config.ieaddr);
			aos[app]->aos_cntrlreg_write(0x20, offset + test_config.waddr0);
			aos[app]->aos_cntrlreg_write(0x28, offset + test_config.waddr1);
			aos[app]->aos_cntrlreg_write(0x30, test_config.rounds);
			aos[app]->aos_cntrlreg_write(0x38, 1);
		}
		
		// end runs
		uint64_t reg_addr0 = 0x40; // round addr
		uint64_t reg_addr1 = 0x20; // stage addr
		uint64_t curr_rounds = 0;
	   	uint64_t stage = 666;
		uint64_t round1_cnt = num_apps;
		bool round1_set[4] = {0};
		uint64_t round2_cnt = num_apps;
		bool round2_set[4] = {0};
		uint64_t round3_cnt = num_apps;
		bool round3_set[4] = {0};

		for (uint64_t app = 0; app < num_apps; ++app) {
			do {
				sleep(.1);

				for (uint64_t a = 0; a < num_apps; ++a) {
					aos[a]->aos_cntrlreg_read(reg_addr0, curr_rounds);
					// round 4 marks the end of the first iteration because there's some initialization stuff that uses round = 0, 1, 2
					if (curr_rounds >= 4 && !round1_set[a]) {
						round1_cnt--;
						round1_set[a] = 1;
						if (round1_cnt == 0) {
							first = high_resolution_clock::now();
							//printf("round1_cnt set\n");
						}
					} else if (curr_rounds >= 5 && !round2_set[a]) {
						round2_cnt--;
						round2_set[a] = 1;
						if (round2_cnt == 0) {
							second = high_resolution_clock::now();
							//printf("round2_cnt set\n");
						}
					} else if (curr_rounds >= 6 && !round3_set[a]) {
						round3_cnt--;
						round3_set[a] = 1;
						if (round3_cnt == 0) {
							third = high_resolution_clock::now();
							//printf("round3_cnt set\n");
						}
					}
				}

				aos[app]->aos_cntrlreg_read(reg_addr0, curr_rounds);
				aos[app]->aos_cntrlreg_read(reg_addr1, stage);
			} while (curr_rounds != rounds+2 || stage != 0);
		}
		end = high_resolution_clock::now();
		if (rounds == 2)
			second = high_resolution_clock::now();
		if (rounds == 1)
			first = high_resolution_clock::now();
		
		// bytes read per round = all vertices' in- and out-degrees (16B) + all inedges (8B) + inedge old PR (8B)
		uint64_t round_read_bytes = num_apps * (n_vert * 16 + n_ie * 16);
		uint64_t total_read_bytes = round_read_bytes * rounds;
		// bytes written per round = new PR for each vertex (8B)
		uint64_t wr_bytes = num_apps * n_vert * 8;
		uint64_t total_wr_bytes = wr_bytes* rounds;
		diff = end - start;
		init_diff = first - start;
		first_diff = second - first;
		second_diff = third - second;
		seconds = diff.count();
		init_seconds = init_diff.count();
		round1_seconds = first_diff.count();
		round2_seconds = second_diff.count();

		uint64_t stream_bytes = num_apps * rounds * (n_vert * 16 + n_ie * 8);
		uint64_t random_bytes = num_apps * rounds * (n_ie * 8);
		double perc_stream = (double)stream_bytes/total_read_bytes * 100;
		double perc_random = (double)random_bytes/total_read_bytes * 100;
		printf("streaming = %lu (%lu%%), random = %lu (%lu%%)\n", 
				stream_bytes, (uint64_t)perc_stream, random_bytes, (uint64_t)perc_random);

		double read_throughput = ((double)total_read_bytes)/seconds/(1<<20);
		double init_read_throughput = ((double)round_read_bytes)/init_seconds/(1<<20);
		double first_read_throughput = ((double)round_read_bytes)/round1_seconds/(1<<20);
		double second_read_throughput = ((double)round_read_bytes)/round2_seconds/(1<<20);
		double init_wr_throughput = ((double)wr_bytes)/init_seconds/(1<<20);
		double first_wr_throughput = ((double)wr_bytes)/round1_seconds/(1<<20);
		double wr_throughput = ((double)total_wr_bytes)/seconds/(1<<20);
         
		printf("total reads: read %lu bytes in %g seconds for %g MiB/s\n", total_read_bytes, seconds, read_throughput);
		// if cold CPU, first round gives throughput information; otherwise is warm CPU + cold FPGA
		printf("first reads: read %lu bytes in %g seconds for %g MiB/s\n", round_read_bytes, init_seconds, init_read_throughput);
		// always gives warm CPU + warm FPGA data
		printf("second reads: read %lu bytes in %g seconds for %g MiB/s\n", round_read_bytes, round1_seconds, first_read_throughput);
		// third round is sometimes more accurate than second (higher throughput, possibly still warming up?)
		printf("third reads: read %lu bytes in %g seconds for %g MiB/s\n", round_read_bytes, round2_seconds, second_read_throughput);

		printf("total writes: wrote %lu bytes in %g seconds for %g MiB/s\n", total_wr_bytes, seconds, wr_throughput);
		printf("first writes: wrote %lu bytes in %g seconds for %g MiB/s\n", wr_bytes, init_seconds, init_wr_throughput);
		printf("second writes: wrote %lu bytes in %g seconds for %g MiB/s\n", wr_bytes, round1_seconds, first_wr_throughput);
	}
	
	for (uint64_t app = 0; app < num_apps; ++app) {
		aos[app]->aos_munmap(addr[app], length);
		aos[app]->aos_file_close(fd[app]);
	}
	
	return 0;
}
