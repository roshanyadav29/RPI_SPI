import spidev

# Create an SPI device object
spi = spidev.SpiDev()
spi.open(0, 0)  # Open SPI bus 0, device (CS) 1
spi.max_speed_hz = 32000000  # Set clock speed to 32 MHz
spi.mode = 0  # Set SPI mode to 0

# Create a buffer for dummy write data (required for SPI reads)
dummy_data = [0x00]  # Only one byte

# Read one byte from the Teensy
print('Reading 1 byte from SPI...')
received_data = spi.xfer2(dummy_data)

# Display the received byte
print('Received byte:', received_data[0])

# Clean up
spi.close()