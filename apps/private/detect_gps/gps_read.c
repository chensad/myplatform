#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <errno.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/select.h>
#include <termios.h>
#include <stdlib.h>

enum {
	GPS_READ_OK = 0,
	GPS_READ_ERROR = -1,
	GPS_READ_TIMEOUT = -2,
};

static speed_t baudrate_to_constant(int baudrate)
{
	switch (baudrate)
	{
	case 2400:
		return B2400;
	case 4800:
		return B4800;
	case 9600:
		return B9600;
	case 115200:
		return B115200;
	default:
		return 0;
	}
}

static void print_serial_status(const char *dev, int baudrate, int timeout_sec)
{
	printf("detect_gps start\n");
	printf("  device  : %s\n", dev);
	printf("  baudrate: %d\n", baudrate);
	printf("  timeout : %d sec\n", timeout_sec);
	fflush(stdout);
}

/* set_opt(fd,115200,8,'N',1) */
int set_opt(int fd, int nSpeed, int nBits, char nEvent, int nStop)
{
	struct termios newtio,oldtio;
	speed_t baud;
	
	if ( tcgetattr( fd,&oldtio) != 0) { 
		perror("SetupSerial 1");
		return -1;
	}
	
	bzero( &newtio, sizeof( newtio ) );
	newtio.c_cflag |= CLOCAL | CREAD; 
	newtio.c_cflag &= ~CSIZE; 

	newtio.c_lflag  &= ~(ICANON | ECHO | ECHOE | ISIG);  /*Input*/
	newtio.c_oflag  &= ~OPOST;   /*Output*/

	switch( nBits )
	{
	case 7:
		newtio.c_cflag |= CS7;
	break;
	case 8:
		newtio.c_cflag |= CS8;
	break;
	}

	switch( nEvent )
	{
	case 'O':
		newtio.c_cflag |= PARENB;
		newtio.c_cflag |= PARODD;
		newtio.c_iflag |= (INPCK | ISTRIP);
	break;
	case 'E': 
		newtio.c_iflag |= (INPCK | ISTRIP);
		newtio.c_cflag |= PARENB;
		newtio.c_cflag &= ~PARODD;
	break;
	case 'N': 
		newtio.c_cflag &= ~PARENB;
	break;
	}

	baud = baudrate_to_constant(nSpeed);
	if (!baud)
	{
		fprintf(stderr, "unsupported baudrate: %d\n", nSpeed);
		return -1;
	}

	cfsetispeed(&newtio, baud);
	cfsetospeed(&newtio, baud);
	
	if( nStop == 1 )
		newtio.c_cflag &= ~CSTOPB;
	else if ( nStop == 2 )
		newtio.c_cflag |= CSTOPB;
	
	newtio.c_cc[VMIN]  = 0;
	newtio.c_cc[VTIME] = 0;

	tcflush(fd,TCIFLUSH);
	
	if((tcsetattr(fd,TCSANOW,&newtio))!=0)
	{
		perror("com set error");
		return -1;
	}
	//printf("set done!\n");
	return 0;
}

int open_port(char *com)
{
	int fd;
	//fd = open(com, O_RDWR|O_NOCTTY|O_NDELAY);
	fd = open(com, O_RDWR|O_NOCTTY);
    if (-1 == fd){
		return(-1);
    }
	
	  if(fcntl(fd, F_SETFL, 0)<0) /* 设置串口为阻塞状态*/
	  {
			printf("fcntl failed!\n");
			return -1;
	  }
  
	  return fd;
}


int read_gps_raw_data(int fd, char *buf, size_t buf_size, int timeout_sec)
{
	int i = 0;
	int iRet;
	char c;
	int start = 0;
	fd_set rfds;
	struct timeval tv;
	
	while (1)
	{
		FD_ZERO(&rfds);
		FD_SET(fd, &rfds);
		tv.tv_sec = timeout_sec;
		tv.tv_usec = 0;

		iRet = select(fd + 1, &rfds, NULL, NULL, &tv);
		if (iRet == 0)
			return GPS_READ_TIMEOUT;
		if (iRet < 0)
			return GPS_READ_ERROR;

		iRet = read(fd, &c, 1);
		if (iRet == 1)
		{
			if (c == '$')
				start = 1;
			if (start)
			{
				if (i >= (int)buf_size - 1)
				{
					buf[0] = '\0';
					return GPS_READ_ERROR;
				}
				buf[i++] = c;
			}
			if (c == '\n' || c == '\r')
            {
                buf[i] = '\0';
				return GPS_READ_OK;
            }
		}
		else
		{
			return GPS_READ_ERROR;
		}
	}
}

/* eg. $GPGGA,082559.00,4005.22599,N,11632.58234,E,1,04,3.08,14.6,M,-5.6,M,,*76"<CR><LF> */
int parse_gps_raw_data(char *buf, char *time, char *lat, char *ns, char *lng, char *ew)
{
	char tmp[10];
	
	if (buf[0] != '$')
		return -1;
	else if (strncmp(buf+3, "GGA", 3) != 0)
		return -1;
	else if (strstr(buf, ",,,,,"))
	{
		printf("Place the GPS to open area\n");
		return -1;
	}
	else {
		//printf("raw data: %s\n", buf);
		sscanf(buf, "%[^,],%[^,],%[^,],%[^,],%[^,],%[^,]", tmp, time, lat, ns, lng, ew);
		return 0;
	}
}


/*
 * ./serial_send_recv <dev>
 */
int main(int argc, char **argv)
{
	int fd;
	int iRet;
	char buf[1000];
	char time[100];
	char Lat[100]; 
	char ns[100]; 
	char Lng[100]; 
	char ew[100];
	int baudrate = 9600;
	int timeout_sec = 3;

	float fLat, fLng;

	/* 1. open */

	/* 2. setup 
	 * 115200,8N1
	 * RAW mode
	 * return data immediately
	 */

	/* 3. write and read */
	
	if (argc < 2 || argc > 3)
	{
		printf("Usage: \n");
		printf("%s <device> [baudrate]\n", argv[0]);
		printf("Example:\n");
		printf("%s /dev/ttymxc5 9600\n", argv[0]);
		return -1;
	}

	if (argc == 3)
	{
		baudrate = atoi(argv[2]);
		if (!baudrate_to_constant(baudrate))
		{
			fprintf(stderr, "invalid baudrate: %s\n", argv[2]);
			return -1;
		}
	}

	print_serial_status(argv[1], baudrate, timeout_sec);

	fd = open_port(argv[1]);
	if (fd < 0)
	{
		printf("open %s err!\n", argv[1]);
		return -1;
	}

	iRet = set_opt(fd, baudrate, 8, 'N', 1);
	if (iRet)
	{
		printf("set port err!\n");
		return -1;
	}

	while (1)
	{
		/* eg. $GPGGA,082559.00,4005.22599,N,11632.58234,E,1,04,3.08,14.6,M,-5.6,M,,*76"<CR><LF>*/
		/* read line */
		iRet = read_gps_raw_data(fd, buf, sizeof(buf), timeout_sec);
		if (iRet == GPS_READ_TIMEOUT)
		{
			printf("read timeout: no GPS data within %d sec\n", timeout_sec);
			fflush(stdout);
			continue;
		}
		if (iRet != GPS_READ_OK)
		{
			perror("read gps data");
			return -1;
		}
		
		/* parse line */
		printf("GPS raw data: %s\n", buf);
		iRet = parse_gps_raw_data(buf, time, Lat, ns, Lng, ew);
		
		/* printf */
		if (iRet == 0)
		{
			printf("Time : %s\n", time);
			printf("ns   : %s\n", ns);
			printf("ew   : %s\n", ew);
			printf("Lat  : %s\n", Lat);
			printf("Lng  : %s\n", Lng);

			/* 纬度格式: ddmm.mmmm */
			sscanf(Lat+2, "%f", &fLat);
			fLat = fLat / 60;
			fLat += (Lat[0] - '0')*10 + (Lat[1] - '0');

			/* 经度格式: dddmm.mmmm */
			sscanf(Lng+3, "%f", &fLng);
			fLng = fLng / 60;
			fLng += (Lng[0] - '0')*100 + (Lng[1] - '0')*10 + (Lng[2] - '0');
			printf("Lng,Lat: %.06f,%.06f\n", fLng, fLat);
		}
	}

	return 0;
}

