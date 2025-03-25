// spi_capture.c - High-speed SPI data capture from Teensy 4.x
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>  // Added for uint8_t definition
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <time.h>
#include <string.h>
#include <signal.h>

#define BUFFER_SIZE 32768
#define READ_SIZE 4096
#define SPI_DEVICE "/dev/spidev0.0"
#define SPI_SPEED 32000000  // 32 MHz

static int running = 1;

// Forward declaration of functions
int setup_spi(int speed);
int read_spi_buffer(int fd, uint8_t *buffer, size_t size);

void signal_handler(int sig) {
    running = 0;
}

int setup_spi(int speed) {
    int fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) {
        perror("Error opening SPI device");
        return -1;
    }

    int mode = SPI_MODE_0;
    if (ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0) {
        perror("Error setting SPI mode");
        close(fd);
        return -1;
    }

    int bits = 8;
    if (ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0) {
        perror("Error setting bits per word");
        close(fd);
        return -1;
    }

    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0) {
        perror("Error setting SPI speed");
        close(fd);
        return -1;
    }

    return fd;
}

int read_spi_buffer(int fd, uint8_t *buffer, size_t size) {
    struct spi_ioc_transfer tr = {
        .tx_buf = (unsigned long)NULL,
        .rx_buf = (unsigned long)buffer,
        .len = size,
        .speed_hz = SPI_SPEED,
        .delay_usecs = 0,
        .bits_per_word = 8,
    };

    return ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
}

int main(int argc, char *argv[]) {
    int buffer_count = 10;
    int display_stats = 0;
    int save_to_file = 1;  // Default save to file
    char filename[256] = "capture.bin";
    
    // Parse arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--count") == 0 && i+1 < argc) {
            buffer_count = atoi(argv[i+1]);
            i++;
        } else if (strcmp(argv[i], "--file") == 0 && i+1 < argc) {
            strncpy(filename, argv[i+1], sizeof(filename)-1);
            i++;
        } else if (strcmp(argv[i], "--display") == 0) {
            display_stats = 1;
        } else if (strcmp(argv[i], "--no-save") == 0) {
            save_to_file = 0;
        }
    }
    
    // Setup signal handler for Ctrl+C
    signal(SIGINT, signal_handler);
    
    // Initialize SPI
    int spi_fd = setup_spi(SPI_SPEED);
    if (spi_fd < 0) return 1;
    
    // Allocate receive buffer
    uint8_t *buffer = (uint8_t*)malloc(BUFFER_SIZE);
    if (!buffer) {
        fprintf(stderr, "Failed to allocate buffer\n");
        close(spi_fd);
        return 1;
    }
    
    // Open output file
    FILE *outfile = NULL;
    if (save_to_file) {
        outfile = fopen(filename, "wb");
        if (!outfile) {
            perror("Error opening output file");
            free(buffer);
            close(spi_fd);
            return 1;
        }
        printf("Saving data to %s\n", filename);
    }
    
    printf("SPI initialized at %d MHz\n", SPI_SPEED/1000000);
    
    // Timing
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    size_t total_bytes = 0;
    for (int i = 0; i < buffer_count && running; i++) {
        printf("Reading buffer %d/%d...\n", i+1, buffer_count);
        
        // Read full buffer in chunks
        for (size_t offset = 0; offset < BUFFER_SIZE && running; offset += READ_SIZE) {
            size_t chunk_size = (offset + READ_SIZE > BUFFER_SIZE) ? (BUFFER_SIZE - offset) : READ_SIZE;
            int bytes_read = read_spi_buffer(spi_fd, buffer + offset, chunk_size);
            if (bytes_read < 0) {
                perror("SPI transfer failed");
                running = 0;
                break;
            }
        }
        
        // Write to file
        if (running) {
            if (outfile) {
                fwrite(buffer, 1, BUFFER_SIZE, outfile);
            }
            total_bytes += BUFFER_SIZE;
            
            if (display_stats) {
                printf("  First bytes: %02X %02X %02X %02X %02X %02X %02X %02X\n",
                       buffer[0], buffer[1], buffer[2], buffer[3],
                       buffer[4], buffer[5], buffer[6], buffer[7]);
            }
        }
    }
    
    // Calculate throughput
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    double mbps = (total_bytes * 8) / (elapsed * 1000000);
    double mbytes_per_sec = total_bytes / (elapsed * 1024 * 1024);
    
    printf("\nCapture complete:\n");
    printf("  Total received: %zu bytes\n", total_bytes);
    printf("  Time elapsed: %.2f seconds\n", elapsed);
    printf("  Throughput: %.2f MB/s (%.2f Mbps)\n", mbytes_per_sec, mbps);
    
    // Clean up
    if (outfile) {
        fclose(outfile);
    }
    free(buffer);
    close(spi_fd);
    
    return 0;
}