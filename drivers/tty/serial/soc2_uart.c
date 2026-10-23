// SPDX-License-Identifier: GPL-2.0
/*
 * SoC2 UART driver
 *
 * Registers (physical 0x20000, kernel virtual 0xa0020000 through the DMW):
 *   0x0  DR      read:  last received byte, the read clears the RX interrupt
 *                write: transmit byte
 *   0x4  STATUS  bit 0: TX busy
 *
 * A received byte raises ESTAT.IS bit 4 (level, cleared by reading DR).
 * There is no TX interrupt and no FIFO, so transmit is polled. The line is
 * fixed at 115200 8N1 in hardware.
 */
#include <linux/console.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/serial.h>
#include <linux/serial_core.h>
#include <linux/tty.h>
#include <linux/tty_flip.h>

#define SOC2_UART_BASE		0xa0020000
#define SOC2_UART_DR		0x0
#define SOC2_UART_STATUS	0x4
#define SOC2_UART_TX_BUSY	0x1

#define SOC2_UART_BAUD		115200
#define PORT_SOC2		200	/* any value other than PORT_UNKNOWN */

static struct uart_driver soc2_uart_driver;
static struct uart_port soc2_port;

static void soc2_putc(struct uart_port *port, int ch)
{
	while (readl(port->membase + SOC2_UART_STATUS) & SOC2_UART_TX_BUSY)
		cpu_relax();
	writel(ch & 0xff, port->membase + SOC2_UART_DR);
}

/*
 * Called from mach_irq_dispatch() when ESTAT.IS bit 4 is set, inside
 * irq_enter()/irq_exit().
 */
void soc2_uart_interrupt(void)
{
	struct uart_port *port = &soc2_port;
	unsigned int ch;

	/* Always read DR: it clears the interrupt even if nobody listens. */
	ch = readl((void __iomem *)SOC2_UART_BASE + SOC2_UART_DR) & 0xff;

	if (!port->state)	/* driver not registered yet */
		return;

	spin_lock(&port->lock);
	port->icount.rx++;
	uart_insert_char(port, 0, 0, ch, TTY_NORMAL);
	spin_unlock(&port->lock);

	tty_flip_buffer_push(&port->state->port);
}

static unsigned int soc2_tx_empty(struct uart_port *port)
{
	return (readl(port->membase + SOC2_UART_STATUS) & SOC2_UART_TX_BUSY) ?
		0 : TIOCSER_TEMT;
}

static void soc2_set_mctrl(struct uart_port *port, unsigned int mctrl)
{
}

static unsigned int soc2_get_mctrl(struct uart_port *port)
{
	return TIOCM_CAR | TIOCM_DSR | TIOCM_CTS;
}

static void soc2_stop_tx(struct uart_port *port)
{
}

/*
 * No TX interrupt: drain the transmit buffer here. Called with port->lock
 * held and interrupts off, about 87 us per character.
 */
static void soc2_start_tx(struct uart_port *port)
{
	struct circ_buf *xmit = &port->state->xmit;

	if (port->x_char) {
		soc2_putc(port, port->x_char);
		port->icount.tx++;
		port->x_char = 0;
	}

	if (uart_tx_stopped(port))
		return;

	while (!uart_circ_empty(xmit)) {
		soc2_putc(port, xmit->buf[xmit->tail]);
		xmit->tail = (xmit->tail + 1) & (UART_XMIT_SIZE - 1);
		port->icount.tx++;
	}

	uart_write_wakeup(port);
}

static void soc2_stop_rx(struct uart_port *port)
{
}

static void soc2_break_ctl(struct uart_port *port, int break_state)
{
}

static int soc2_startup(struct uart_port *port)
{
	return 0;
}

static void soc2_shutdown(struct uart_port *port)
{
}

static void soc2_set_termios(struct uart_port *port, struct ktermios *termios,
			     struct ktermios *old)
{
	unsigned long flags;

	/* The hardware is fixed at 115200 8N1. */
	termios->c_cflag &= ~(CSIZE | CSTOPB | PARENB | PARODD | CRTSCTS | CMSPAR);
	termios->c_cflag |= CS8 | CLOCAL;
	tty_termios_encode_baud_rate(termios, SOC2_UART_BAUD, SOC2_UART_BAUD);

	spin_lock_irqsave(&port->lock, flags);
	uart_update_timeout(port, termios->c_cflag, SOC2_UART_BAUD);
	spin_unlock_irqrestore(&port->lock, flags);
}

static const char *soc2_type(struct uart_port *port)
{
	return port->type == PORT_SOC2 ? "SoC2 UART" : NULL;
}

static void soc2_release_port(struct uart_port *port)
{
}

static int soc2_request_port(struct uart_port *port)
{
	return 0;
}

static void soc2_config_port(struct uart_port *port, int flags)
{
	if (flags & UART_CONFIG_TYPE)
		port->type = PORT_SOC2;
}

static int soc2_verify_port(struct uart_port *port, struct serial_struct *ser)
{
	return 0;
}

static const struct uart_ops soc2_uart_ops = {
	.tx_empty	= soc2_tx_empty,
	.set_mctrl	= soc2_set_mctrl,
	.get_mctrl	= soc2_get_mctrl,
	.stop_tx	= soc2_stop_tx,
	.start_tx	= soc2_start_tx,
	.stop_rx	= soc2_stop_rx,
	.break_ctl	= soc2_break_ctl,
	.startup	= soc2_startup,
	.shutdown	= soc2_shutdown,
	.set_termios	= soc2_set_termios,
	.type		= soc2_type,
	.release_port	= soc2_release_port,
	.request_port	= soc2_request_port,
	.config_port	= soc2_config_port,
	.verify_port	= soc2_verify_port,
};

/*
 * Statically initialised so the console can print before the driver is
 * registered. serial_core does not re-initialise the lock of a console port.
 */
static struct uart_port soc2_port = {
	.membase	= (void __iomem *)SOC2_UART_BASE,
	.mapbase	= 0x20000,
	.iotype		= UPIO_MEM32,
	.uartclk	= SOC2_UART_BAUD * 16,
	.fifosize	= 1,
	.ops		= &soc2_uart_ops,
	.flags		= UPF_BOOT_AUTOCONF,
	.line		= 0,
	.lock		= __SPIN_LOCK_UNLOCKED(soc2_port.lock),
};

/* Console */

static void soc2_console_putchar(struct uart_port *port, int ch)
{
	soc2_putc(port, ch);
}

static void soc2_console_write(struct console *co, const char *s,
			       unsigned int count)
{
	struct uart_port *port = &soc2_port;
	unsigned long flags;
	int locked = 1;

	if (oops_in_progress)
		locked = spin_trylock_irqsave(&port->lock, flags);
	else
		spin_lock_irqsave(&port->lock, flags);

	uart_console_write(port, s, count, soc2_console_putchar);

	if (locked)
		spin_unlock_irqrestore(&port->lock, flags);
}

static struct console soc2_console = {
	.name	= "ttyS",
	.write	= soc2_console_write,
	.device	= uart_console_device,
	.flags	= CON_PRINTBUFFER,
	.index	= -1,
	.data	= &soc2_uart_driver,
};

static struct uart_driver soc2_uart_driver = {
	.owner		= THIS_MODULE,
	.driver_name	= "soc2_uart",
	.dev_name	= "ttyS",
	.major		= TTY_MAJOR,
	.minor		= 64,		/* ttyS0; keep CONFIG_SERIAL_8250 off */
	.nr		= 1,
	.cons		= &soc2_console,
};

static int __init soc2_console_init(void)
{
	register_console(&soc2_console);
	return 0;
}
console_initcall(soc2_console_init);

static int __init soc2_uart_init(void)
{
	int ret;

	ret = uart_register_driver(&soc2_uart_driver);
	if (ret)
		return ret;

	ret = uart_add_one_port(&soc2_uart_driver, &soc2_port);
	if (ret)
		uart_unregister_driver(&soc2_uart_driver);

	return ret;
}
device_initcall(soc2_uart_init);
