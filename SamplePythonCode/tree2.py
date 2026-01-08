#!/usr/bin/python3

from gpiozero import LEDBoard
from gpiozero.tools import random_values
from signal import pause
from typing import Generator
import math
import random
import time


def myrandom(start: float, stop: float, step: float) -> Generator:
    while True:
        time.sleep(random.random())
        x = start
        while x < stop:
            tx = math.sin(x)
            if tx < 0:
                x += step
                yield 0
            elif tx > 0.3:
                yield 0.3
            else:
                yield tx
            x += step


tree = LEDBoard(*range(2,28), pwm=True)
for led in tree:
    led.source_delay = 0.1
    led.source = myrandom(0, 2 * math.pi, 0.05)

pause()
