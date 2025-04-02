#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <time.h>
#include <gpiod.h>

// Configuration
#define SPI_DEVICE      "/dev/spidev0.0"
#define BUFFER_SIZE     4096          // Number of 32-bit elements
#define BYTES_PER_ELEM  4             // Bytes per 32-bit element
#define TOTAL_BYTES     (BUFFER_SIZE * BYTES_PER_ELEM)
#define CHUNK_SIZE      256           // Size of each transfer chunk
#define GPIO_CHIP       "/dev/gpiochip0"
#define DATA_READY_PIN  25            // GPIO pin for data ready

// Function prototypes
int setup_spi(int speed_hz);
struct gpiod_chip* setup_gpio(void);
void wait_for_data_ready_high(struct gpiod_chip* chip, struct gpiod_line* line);
void wait_for_data_ready_low(struct gpiod_chip* chip, struct gpiod_line* line);
void transfer_data(int fd, uint8_t* buffer);
void print_buffer_stats(uint8_t* buffer, uint32_t* elements);
void convert_to_elements(uint8_t* buffer, uint32_t* elements);
void check_pattern(uint32_t* elements);
double get_time_diff_ms(struct timespec start, struct timespec end);

int main() {
    int spi_fd;
    uint8_t* byte_buffer;
    uint32_t* element_buffer;
    struct gpiod_chip* gpio_chip;
    struct gpiod_line* data_ready_line;
    struct timespec start_time, end_time;
    int transaction_count = 0;
    
    printf("SPI Master 32-bit Transfer Program\n");
    
    // Allocate memory for buffers
    byte_buffer = (uint8_t*)malloc(TOTAL_BYTES);
    element_buffer = (uint32_t*)malloc(BUFFER_SIZE * sizeof(uint32_t));
    
    if (!byte_buffer || !element_buffer) {
        fprintf(stderr, "Memory allocation failed\n");
        return -1;
    }
    
    // Setup SPI (8MHz)
    spi_fd = setup_spi(8000000);
    if (spi_fd < 0) {
        free(byte_buffer);
        free(element_buffer);
        return -1;
    }
    
    // Setup GPIO
    gpio_chip = setup_gpio();
    if (!gpio_chip) {
        close(spi_fd);
        free(byte_buffer);
        free(element_buffer);
        return -1;
    }
    
    // Get data ready line
    data_ready_line = gpiod_chip_get_line(gpio_chip, DATA_READY_PIN);
    if (!data_ready_line) {
        fprintf(stderr, "Unable to get GPIO line %d\n", DATA_READY_PIN);
        gpiod_chip_close(gpio_chip);
        close(spi_fd);
        free(byte_buffer);
        free(element_buffer);
        return -1;
    }
    
    // Configure data ready line as input
    if (gpiod_line_request_input(data_ready_line, "rpi_spi") < 0) {
        fprintf(stderr, "Unable to configure GPIO line %d as input\n", DATA_READY_PIN);
        gpiod_line_release(data_ready_line);
        gpiod_chip_close(gpio_chip);
        close(spi_fd);
        free(byte_buffer);
        free(element_buffer);
        return -1;
    }
    
    printf("SPI and GPIO initialized\n");
    printf("Waiting for data ready signal (HIGH) from Teensy...\n");
    
    // Main loop
    while (transaction_count < 10) { // Limit to 10 transactions for safety
        // Wait for data ready signal (HIGH)
        wait_for_data_ready_high(gpio_chip, data_ready_line);
        
        transaction_count++;
        printf("\nTransaction #%d - Data ready HIGH detected\n", transaction_count);
        
        // Transfer data
        clock_gettime(CLOCK_MONOTONIC, &start_time);
        transfer_data(spi_fd, byte_buffer);
        clock_gettime(CLOCK_MONOTONIC, &end_time);
        
        double transfer_time_ms = get_time_diff_ms(start_time, end_time);
        printf("Transfer complete: %.2f ms (%.2f KB/s)\n", 
               transfer_time_ms, 
               (TOTAL_BYTES / 1024.0) / (transfer_time_ms / 1000.0));
        
        // Convert bytes to 32-bit elements
        clock_gettime(CLOCK_MONOTONIC, &start_time);
        convert_to_elements(byte_buffer, element_buffer);
        clock_gettime(CLOCK_MONOTONIC, &end_time);
        printf("Conversion time: %.2f ms\n", get_time_diff_ms(start_time, end_time));
        
        // Analyze buffer contents
        print_buffer_stats(byte_buffer, element_buffer);
        check_pattern(element_buffer);
        
        // Wait for data ready to go low (transfer complete)
        printf("Waiting for Teensy to signal completion (data ready LOW)...\n");
        wait_for_data_ready_low(gpio_chip, data_ready_line);
        printf("Data ready LOW - transfer complete\n");
        
        // Save data to file if needed
        char filename[64];
        sprintf(filename, "spi_data_transaction_%d.bin", transaction_count);
        FILE* outfile = fopen(filename, "wb");
        if (outfile) {
            fwrite(element_buffer, sizeof(uint32_t), BUFFER_SIZE, outfile);
            fclose(outfile);
            printf("Data saved to %s\n", filename);
        }
        
        printf("Ready for next transaction\n");
        sleep(1);
    }
    
    // Cleanup
    printf("Cleaning up...\n");
    gpiod_line_release(data_ready_line);
    gpiod_chip_close(gpio_chip);
    close(spi_fd);
    free(byte_buffer);
    free(element_buffer);
    
    printf("SPI communication ended\n");
    return 0;
}

// Set up SPI device
int setup_spi(int speed_hz) {
    int fd;
    uint8_t mode = SPI_MODE_0;
    uint8_t bits = 8;
    
    fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) {
        perror("Failed to open SPI device");
        return -1;
    }
    
    // Set SPI mode
    if (ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0) {
        perror("Failed to set SPI mode");
        close(fd);
        return -1;
    }
    
    // Set bits per word
    if (ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0) {
        perror("Failed to set bits per word");
        close(fd);
        return -1;
    }
    
    // Set max speed
    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed_hz) < 0) {
        perror("Failed to set SPI speed");
        close(fd);
        return -1;
    }
    
    return fd;
}

// Set up GPIO
struct gpiod_chip* setup_gpio(void) {
    struct gpiod_chip* chip = gpiod_chip_open(GPIO_CHIP);
    if (!chip) {
        perror("Failed to open GPIO chip");
    }
    return chip;
}

// Wait for data ready signal to go HIGH
void wait_for_data_ready_high(struct gpiod_chip* chip, struct gpiod_line* line) {
    int value;
    time_t start_time = time(NULL);
    
    while (1) {
        value = gpiod_line_get_value(line);
        if (value == 1) {
            // Debounce - check again after a short delay
            usleep(10000);  // 10ms
            value = gpiod_line_get_value(line);
            if (value == 1) {
                return;
            }
        }
        
        // Print status every 5 seconds
        if (time(NULL) - start_time >= 5) {
            printf("Still waiting for data ready (HIGH)... Current: %d\n", value);
            start_time = time(NULL);
        }
        
        usleep(10000);  // 10ms delay
    }
}

// Wait for data ready signal to go LOW
void wait_for_data_ready_low(struct gpiod_chip* chip, struct gpiod_line* line) {
    int value;
    time_t start_time = time(NULL);
    time_t timeout_seconds = 10;  // 10 second timeout
    
    while (time(NULL) - start_time < timeout_seconds) {
        value = gpiod_line_get_value(line);
        if (value == 0) {
            // Debounce - check again after a short delay
            usleep(20000);  // 20ms
            value = gpiod_line_get_value(line);
            if (value == 0) {
                return;
            }
        }
        usleep(10000);  // 10ms delay
    }
    
    printf("WARNING: Timeout waiting for data ready LOW\n");
}

// Transfer data in chunks
void transfer_data(int fd, uint8_t* buffer) {
    struct spi_ioc_transfer transfer;
    uint8_t tx_buffer[CHUNK_SIZE];
    uint8_t rx_buffer[CHUNK_SIZE];
    int bytes_transferred = 0;
    int chunks = TOTAL_BYTES / CHUNK_SIZE;
    int remainder = TOTAL_BYTES % CHUNK_SIZE;
    int i, chunk_size;
    struct timespec chunk_start, chunk_end;
    
    printf("Transferring %d bytes in %d chunks of %d bytes plus %d bytes\n",
           TOTAL_BYTES, chunks, CHUNK_SIZE, remainder);
    
    // Zero-fill the transmit buffer
    memset(tx_buffer, 0, CHUNK_SIZE);
    
    // Process full chunks
    for (i = 0; i < chunks; i++) {
        chunk_size = CHUNK_SIZE;
        
        // Prepare transfer structure
        memset(&transfer, 0, sizeof(transfer));
        transfer.tx_buf = (unsigned long)tx_buffer;
        transfer.rx_buf = (unsigned long)rx_buffer;
        transfer.len = chunk_size;
        transfer.speed_hz = 8000000;
        transfer.delay_usecs = 0;
        transfer.bits_per_word = 8;
        
        // Transfer data
        clock_gettime(CLOCK_MONOTONIC, &chunk_start);
        if (ioctl(fd, SPI_IOC_MESSAGE(1), &transfer) < 0) {
            perror("SPI transfer failed");
            return;
        }
        clock_gettime(CLOCK_MONOTONIC, &chunk_end);
        
        // Copy received data to buffer
        memcpy(buffer + bytes_transferred, rx_buffer, chunk_size);
        bytes_transferred += chunk_size;
        
        // Report progress
        if (i == 0 || i == chunks-1 || i % 16 == 0) {
            double chunk_time_ms = get_time_diff_ms(chunk_start, chunk_end);
            printf("Chunk %d/%d: %d bytes in %.2f ms (%.2f KB/s)\n", 
                   i+1, chunks+(remainder>0?1:0), chunk_size, 
                   chunk_time_ms, 
                   (chunk_size / 1024.0) / (chunk_time_ms / 1000.0));
        }
        
        // Report progress at 10% intervals
        int progress_pct = (bytes_transferred * 100) / TOTAL_BYTES;
        if (progress_pct % 10 == 0 && progress_pct > 0) {
            static int last_reported_pct = -1;
            if (progress_pct != last_reported_pct) {
                printf("Progress: %d%% (%d/%d bytes)\n", 
                       progress_pct, bytes_transferred, TOTAL_BYTES);
                last_reported_pct = progress_pct;
            }
        }
        
        // Add small delay between chunks
        usleep(5000);  // 5ms
    }
    
    // Process remainder if any
    if (remainder > 0) {
        chunk_size = remainder;
        
        // Prepare transfer structure
        memset(&transfer, 0, sizeof(transfer));
        transfer.tx_buf = (unsigned long)tx_buffer;
        transfer.rx_buf = (unsigned long)rx_buffer;
        transfer.len = chunk_size;
        transfer.speed_hz = 8000000;
        transfer.delay_usecs = 0;
        transfer.bits_per_word = 8;
        
        // Transfer data
        if (ioctl(fd, SPI_IOC_MESSAGE(1), &transfer) < 0) {
            perror("SPI transfer failed");
            return;
        }
        
        // Copy received data to buffer
        memcpy(buffer + bytes_transferred, rx_buffer, chunk_size);
        bytes_transferred += chunk_size;
    }
    
    printf("Transfer complete: %d bytes transferred\n", bytes_transferred);
}

// Convert bytes to 32-bit elements
void convert_to_elements(uint8_t* buffer, uint32_t* elements) {
    int i;
    printf("Converting %d bytes to %d 32-bit elements...\n", TOTAL_BYTES, BUFFER_SIZE);
    
    for (i = 0; i < BUFFER_SIZE; i++) {
        elements[i] = (uint32_t)buffer[i*4] | 
                     ((uint32_t)buffer[i*4+1] << 8) | 
                     ((uint32_t)buffer[i*4+2] << 16) | 
                     ((uint32_t)buffer[i*4+3] << 24);
    }
}

// Print stats about the received buffer
void print_buffer_stats(uint8_t* buffer, uint32_t* elements) {
    int i;
    
    // Print first few bytes
    printf("First 16 bytes: ");
    for (i = 0; i < 16; i++) {
        printf("%02X ", buffer[i]);
    }
    printf("\n");
    
    // Print first few 32-bit elements
    printf("First 8 32-bit elements: ");
    for (i = 0; i < 8; i++) {
        printf("%u ", elements[i]);
    }
    printf("\n");
}

// Check for pattern (even or odd)
void check_pattern(uint32_t* elements) {
    int i;
    int even_count = 0;
    int odd_count = 0;
    
    // Check first 10 elements
    for (i = 0; i < 10; i++) {
        if (elements[i] % 2 == 0) {
            even_count++;
        } else {
            odd_count++;
        }
    }
    
    if (even_count == 10) {
        printf("Detected EVEN number sequence (Buffer A)\n");
    } else if (odd_count == 10) {
        printf("Detected ODD number sequence (Buffer B)\n");
    } else {
        printf("WARNING: Received data does not match expected pattern\n");
        printf("First 20 values mod 2: ");
        for (i = 0; i < 20; i++) {
            printf("%d ", elements[i] % 2);
        }
        printf("\n");
    }
}

// Calculate time difference in milliseconds
double get_time_diff_ms(struct timespec start, struct timespec end) {
    return ((end.tv_sec - start.tv_sec) * 1000.0) + 
           ((end.tv_nsec - start.tv_nsec) / 1000000.0);
}