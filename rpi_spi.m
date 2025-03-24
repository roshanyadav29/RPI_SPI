% filepath: /home/admin/RPI_SPI/rpi_spi.m

% Create a Raspberry Pi object
rpi = raspi();

% Create an SPI device object
spiDev = spidev(rpi, 'CE1', 0, 32e6); % Use 'CE0' for chip select 0

% Send a command to request data (this depends on your SPI slave setup)
data = writeRead(spiDev, uint8(0x01));

% Display the received data
disp(['Received data: ', num2str(data)]);

% Clean up
clear spiDev;
clear rpi;