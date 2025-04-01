/**
 * Raspberry Pi SPI Communication with Double Buffer
 * Equivalent to MATLAB implementation
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
#include <bcm2835.h>

// Constants
#define DATA_READY_PIN RPI_GPIO_P1_15  // GPIO22, pin 15 on header
#define SPI_CS         BCM2835_SPI_CS0 // Chip Select 0
#define BUFFER_SIZE    4096            // Buffer size to match Teensy
#define SPI_CLOCK      16000000        // 16 MHz SPI clock

// Function prototypes
double get_time_sec();
void delay_ms(int milliseconds);

int main() {
    uint8_t receivedData[BUFFER_SIZE];
    int transactionCount = 0;
    double startTime, currentTime, timeout = 120.0; // 120 seconds timeout
    double waitTime;
    
    printf("Starting SPI Transaction with Double Buffer\n");
    
    // Initialize the bcm2835 library
    if (!bcm2835_init()) {
        printf("Error: Could not initialize bcm2835 library\n");
        return 1;
    }
    
    // Configure GPIO pin for data ready signal
    bcm2835_gpio_fsel(DATA_READY_PIN, BCM2835_GPIO_FSEL_INPT);
    bcm2835_gpio_set_pud(DATA_READY_PIN, BCM2835_GPIO_PUD_DOWN); // Pull-down
    
    // Initialize SPI
    if (!bcm2835_spi_begin()) {
        printf("Error: Could not initialize SPI\n");
        bcm2835_close();
        return 1;
    }
    
    // Configure SPI settings
    bcm2835_spi_setBitOrder(BCM2835_SPI_BIT_ORDER_MSBFIRST);
    bcm2835_spi_setDataMode(BCM2835_SPI_MODE0);
    bcm2835_spi_setClockDivider(BCM2835_SPI_CLOCK_DIVIDER_16); // ~16 MHz on RPi3
    bcm2835_spi_chipSelect(SPI_CS);
    bcm2835_spi_setChipSelectPolarity(SPI_CS, LOW);
    
    printf("Waiting for data ready signal...\n");
    
    // Start timing
    startTime = get_time_sec();
    
    // Polling loop
    while ((currentTime = get_time_sec()) - startTime < timeout) {
        // Check if data is ready with debounce
        if (bcm2835_gpio_lev(DATA_READY_PIN)) {
            delay_ms(10); // Simple debounce, 10ms
            
            // Double check data ready signal
            if (bcm2835_gpio_lev(DATA_READY_PIN)) {
                transactionCount++;
                printf("Transaction #%d - Data ready signal detected\n", transactionCount);
                
                // Read data in chunks from SPI
                for (int i = 0; i < BUFFER_SIZE; i++) {
                    // Send dummy byte to trigger Teensy to send data
                    receivedData[i] = bcm2835_spi_transfer(0);
                }
                
                // Display statistics of received data
                printf("Received %d bytes\n", BUFFER_SIZE);
                printf("First 10 bytes: ");
                for (int i = 0; i < 10 && i < BUFFER_SIZE; i++) {
                    printf("%d ", receivedData[i]);
                }
                printf("\n");
                
                // Wait for data ready signal to go LOW
                printf("Waiting for data ready signal to go LOW\n");
                waitTime = get_time_sec();
                while (bcm2835_gpio_lev(DATA_READY_PIN) && 
                       (get_time_sec() - waitTime < 5.0)) {
                    delay_ms(10);
                }
                
                printf("Ready for next transaction\n");
            }
        }
        
        delay_ms(10); // Add delay to reduce CPU usage
    }
    
    printf("Polling timeout reached\n");
    
    // Clean up
    bcm2835_spi_end();
    bcm2835_close();
    printf("SPI communication ended\n");
    
    return 0;
}

// Get current time in seconds
double get_time_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

// Delay for milliseconds
void delay_ms(int milliseconds) {
    struct timespec ts;
    ts.tv_sec = milliseconds / 1000;
    ts.tv_nsec = (milliseconds % 1000) * 1000000;
    nanosleep(&ts, NULL);
}