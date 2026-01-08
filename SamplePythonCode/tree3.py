#!/usr/bin/python3

from gpiozero import LEDBoard
from gpiozero.tools import random_values
from signal import pause
from typing import Generator
from datetime import datetime, timedelta
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

period = timedelta(minutes=1)
while True: #do forever
    next_time = datetime.now() + period
    if random.randint(1, 10) % 2 == 0:
        print("A")
        while True:
            for led in tree:
                led.source_delay = 0.1
                led.source = myrandom(0, 2 * math.pi, 0.05)
            if datetime.now() > next_time:
                break
    else:
        print("B")
        while True:
            for led in tree:
                led.source_delay = 0.1
                led.source = random_values()
            if datetime.now() > next_time:
                break
    if random.randint(1, 10) % 3 == 0:
        for led in tree:
            print ("Reset")
            time.sleep(0.25)
            led.source = [0,0,0,0,0,0,0,0,0]
    if random.randint(1, 10) == 6:
        for led in tree:
            print ("Lightup")
            time.sleep(0.25)
            led.source = [1,1,1,1,1,1,1,1,1]
ß