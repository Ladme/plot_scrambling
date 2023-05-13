#!/bin/bash

# Released under MIT License.
# Copyright (c) 2023 Ladislav Bartos / RoVa Lab
# Version 1.0.0

module add anaconda3

python - "$@" << EOF

import sys, os
import argparse
import warnings
import numpy as np
import matplotlib as mpl
import matplotlib.pyplot as plt

class Experiment:
    """
    Class for a single dithionite assay experiment.
    """

    def __init__(self, file_name: str, timing: tuple[int, int], data_format: str):
        """
        Initialize an experiment.

        Parameters:
        - file_name (str): Path to the file containing the measured data.
        - timing (tuple[int, int]): Time at which normalization should start and at which dithionite was added.
        - data_format (str): Format of the file containing the measured data.
        """

        self.file_name = file_name
        self.timing = timing
        self.data_format = data_format

        # list of times at which data were measured
        self.times = []

        # list of measured values
        self.values = []
    
    def readFluoressence(self) -> None:
        """
        Read the experimental data from FluorEssence file.
        """

        for line in open(self.file_name):
            try:
                l = [float(x) for x in line.split()]
                self.times.append(int(round(l[0], 0)))
                self.values.append(l[1])
            
            except ValueError:
                print("Skipping line in", self.file_name, line[:-1] if len(line) < 40 else line[:40] + " (...)", file = sys.stderr)

    def readEzspecDatapoints(self) -> None:
        """
        Read the experimental data from EzSpec DataPoints file.
        """

        for line in open(self.file_name):
            if line.strip() == "": continue

            try:
                split = line.split()
                try:
                    x_parsed = float(split[0])
                except ValueError:
                    x_parsed = float(split[0][2:])
                self.times.append(int(round(x_parsed, 0)))
                self.values.append(float(split[1]))
            
            except ValueError:
                print("Skipping line in", self.file_name, line[:-1] if len(line) < 40 else line[:40] + " (...)", file = sys.stderr)

    
    def readEzspecCompatible(self) -> None:
        """
        Read the experimental data from EzSpecCompatible file.
        """

        for (i, line) in enumerate(open(self.file_name)):
            if i < 4: 
                print("Skipping line in", self.file_name, line[:-1] if len(line) < 40 else line[:40] + " (...)", file = sys.stderr)
                continue

            try:
                l = [float(x) for x in line.split()]
                if len(l) < 2: raise ValueError
                self.times.append(int(round(l[0], 0)))
                self.values.append(l[1])
            
            except ValueError:
                print("Skipping line in", self.file_name, line[:-1] if len(line) < 40 else line[:40] + " (...)", file = sys.stderr)
    
    def readEzspecTable(self) -> None:
        """
        Read the experimental data from EzSpec TableHeaderData file.
        """

        for line in open(self.file_name):
            try:
                l = [float(x) for x in line.split()]
                self.times.append(int(round(l[1], 0)))
                self.values.append(l[2])
            
            except ValueError:
                print("Skipping line in", self.file_name, line[:-1] if len(line) < 40 else line[:40] + " (...)", file = sys.stderr)

    
    def identifyDataFormat(self) -> bool:
        """
        Identify the data format of the provided file.

        Returns:
        - bool: True if the data format is successfully identified, else False.
        """
        
        for (i, line) in enumerate(open(self.file_name)):
            if i == 0 and ord(line[0]) == 65279:
                if "Data" in line:
                    self.data_format = "tableheader"
                else:
                    self.data_format = "datapoints"
                return True
            
            if i == 0 and "A" in line:
                self.data_format = "fluoressence"
                return True

            if i == 2 and "CCD" in line and "Ex.Filter" in line and "Em.Polz" in line and "Em.Filter" in line and "Ref" in line:
                self.data_format = "ezspec"
                return True
        

            if i >= 3: 
                return False
    
    def readData(self) -> None:
        """
        Read data for the measurement and identify the data format if needed.
        """

        converter = {"fluoressence": self.readFluoressence, \
                     "datapoints": self.readEzspecDatapoints, \
                     "ezspec": self.readEzspecCompatible, \
                     "tableheader": self.readEzspecTable}
        
        if self.data_format not in converter:
            if self.identifyDataFormat():
                print(f"Identified data format of file '{self.file_name}': {self.data_format}")
            else:
                raise ValueError(f"Could not identify the data format of file '{self.file_name}'.")

        return converter[self.data_format]()
    
    def normalizeData(self) -> None:
        """
        Shift and normalize the data from the experiment.
        """
        # get values for normalization
        start, end = self.timing
        if start is None:
            start = 0

        norm_time = (index_closest(self.times, start), index_closest(self.times, end))
        norm_values = self.values[norm_time[0]:norm_time[1]]
        norm_average = np.average(norm_values)

        # shift all times based on the closest valid time from 'end'
        shift = min(self.times, key = lambda x: abs(x - end))
        for i in range(len(self.times)):
            self.times[i] -= shift
        
        # normalize all values
        for i in range(len(self.values)):
            self.values[i] /= norm_average


class Block:
    """
    Class for a block of measurements.
    """

    def __init__(self, block_name: str):
        """
        Initialize a block of measurements.
        """

        # name of the block of measurements (to be used in legend)
        self.block_name = block_name

        # list of measurements
        self.measurements = []

        # values from averaged measurements
        self.times = []
        self.values = []
        self.errors = []
    
    def addExperiment(self, measurement: Experiment) -> None:
        """
        Add a new experiment to the block of measurements.
        """

        self.measurements.append(measurement)
    
    def measurementsAverage(self) -> None:
        """
        Compute the average of all measurements in the block.
        """

        for (t, time) in enumerate(self.measurements[0].times):
            curr_val = []
            invalid_time = False

            for measurement in self.measurements:
                
                if time not in measurement.times:
                    invalid_time = True
                    break
                
                curr_val.append(measurement.values[index_closest(measurement.times, time)])
            
            if not invalid_time:
                self.times.append(time)
                self.values.append(np.average(curr_val))
                self.errors.append(np.std(curr_val))
    
    def plot(self, chart: mpl.axes.Axes, color: str = None) -> None:
        """
        Plot the measured data.
        """

        if color is None:
            chart.plot(self.times, self.values, label = self.block_name, linewidth = 2)
        else:
            chart.plot(self.times, self.values, color = color, label = self.block_name, linewidth = 2)
        
        minima = [x - y for (x, y) in zip(self.values, self.errors)]
        maxima = [x + y for (x, y) in zip(self.values, self.errors)]

        if color is None:
            chart.fill_between(self.times, minima, maxima, alpha = 0.15)
        else:
            chart.fill_between(self.times, minima, maxima, color = color, alpha = 0.15)


    def process(self, chart: mpl.axes.Axes, color: str = None) -> None:
        """
        Process all measurements in this block and plot the result.
        """

        for measurement in self.measurements:
            measurement.readData()
            measurement.normalizeData()
        
        self.measurementsAverage()

        self.plot(chart, color)

class Measurements:
    """
    Class for a list of dithionite assay measurements distributed into blocks.
    """
    
    def __init__(self, file_name: str, data_format: str, time_range: tuple[int, int], colors: list[str], output_name: str):
        """
        Initialize the Measurements object.

        Parameters:
        - file_name (str): Path to the measurements file.
        - data_format (str): Enforced format of the measurements.
        - time_range (tuple[int, int]): Range of times that should be shown in the final chart.
        - colors (list[str]): Colors to use for plots.
        - output_name (str): Name of the output file.
        """

        self.file_name = file_name
        self.data_format = data_format
        self.time_range = time_range
        self.colors = colors
        self.output_name = output_name

        # list of measurement blocks
        self.blocks = []
    
    def parseTiming(self, string) -> tuple[int, int]:
        """
        Parse timing values for a specific measurement.

        Parameters:
        - string (str): Timing specification.

        Returns:
        - tuple[int, int]: Parsed timing values.
        """

        if "-" in string:
            raw_timing = string.split("-")
            try:
                return tuple(int(num) for num in raw_timing)
            except ValueError:
                raise ValueError(f"Could not parse Measurements file. Could not parse time specification.")
        else:
            try:
                return (None, int(string))
            except ValueError:
                raise ValueError(f"Could not parse Measurements file. Could not parse time specification.")


    def parseMeasurements(self) -> None:
        """
        Parse the measurements file and obtain a list of measurements.
        """

        dir_path = os.path.dirname(self.file_name)
        if dir_path == "": dir_path = "."

        for line in open(self.file_name):
            if line.strip() == "": continue

            if line[0] == ">":
                block_name = line[1:].strip()
                if len(block_name) > 20:
                    warnings.warn("Warning. Block name is too long. This may cause issues with legend visualization.")

                self.blocks.append(Block(block_name))
            
            else:
                split = line.split()
                if len(split) < 2:
                    raise ValueError("Could not parse Measurements file. Line is too short.")

                experiment = Experiment(dir_path + "/" + ' '.join(split[0:-1]), self.parseTiming(split[-1]), self.data_format)
                try:
                    self.blocks[-1].addExperiment(experiment)
                except IndexError:
                    raise IndexError("Could not parse Measurements file. Block not found.")

    def process(self) -> None:
        """
        Process all measurements and generate the final chart.
        """

        self.parseMeasurements()

        if len(self.colors) > 1 and len(self.colors) != len(self.blocks):
            raise ValueError("Number of provided colors does not match the number of blocks.")

        fig = plt.figure(figsize=(5, 4.5), dpi=100)

        chart = fig.add_subplot(111)

        for (i, block) in enumerate(self.blocks):
            color_to_use = None
            if len(self.colors) == 1: color_to_use = self.colors[0]
            elif len(self.colors) > 1: color_to_use = self.colors[i]
            elif len(self.colors) == 0 and len(self.blocks) == 1: color_to_use = "black"

            block.process(chart, color_to_use)
        
        chart.set_ylim([0, 1.2])
        chart.set_xlim([-self.time_range[0] if self.time_range[0] is not None else None, self.time_range[1]])
        chart.set_ylabel("normalized intensity", fontsize = 15)
        chart.set_xlabel("time [s]", fontsize = 15)
        chart.tick_params(
            axis='both', 
            which='major', 
            labelsize=13, 
            direction='in', 
            width=1.5, 
            length = 7, 
            bottom = True, 
            top = True, 
            left = True, 
            right = True)
        chart.grid(True, "major", linestyle = ":", color = "black")

        # set border thickness
        chart.spines["bottom"].set_linewidth(1.5)
        chart.spines["top"].set_linewidth(1.5)
        chart.spines["right"].set_linewidth(1.5)
        chart.spines["left"].set_linewidth(1.5)

        if len(self.blocks) == 1:
            chart.set_title(self.blocks[0].block_name, fontsize = 17)
        else:
            leg = chart.legend(loc='upper right',
                            bbox_to_anchor=(0.98, 0.98),
                            fontsize=11,
                            edgecolor="black",
                            framealpha=1)

            leg.get_frame().set_linewidth(1.5)

        plt.tight_layout()
        plt.savefig(self.output_name, dpi = 200)

def index_closest(lst: list[float], target: float) -> int:
    """
    Return an index of the value in a list that is closest to provided target.
    """

    return min(range(len(lst)), key = lambda i: abs(lst[i] - target))

def parse_timerange_arg(string: str):
    """
    Parse timerange option.
    """
    try:
        values = string.split(",")
        if len(values) != 2:
            raise argparse.ArgumentTypeError("Invalid format. Expected two integers separated by a comma.")
        return tuple(map(int, values))
    except ValueError:
        raise argparse.ArgumentTypeError("Invalid format. Expected two integers separated by a comma.")

def parse_colors_arg(string: str):
    """
    Parse colors option.
    """
    return string.split(",")

def parse_arguments() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description='''The script is designed to plot measured data obtained from a dithionite assay. 
        To use the script, a file containing a list of measurements organized in blocks must be provided. 
        If no file is specified, the default file named 'Measurements' will be used. 
        The format of the file involves each block starting with the '>' symbol, followed by a brief 
        description (pereferably less than 20 characters). Subsequent lines in each block should include 
        (1) the name of the input file generated by either FluorEssence or EzSpec software, 
        and (2) the corresponding time at which dithionite was added.''')
    
    parser.add_argument("file", metavar = "Measurements file", type = str, nargs = "?",
        default = "Measurements", help = "file with a list of measurements")

    parser.add_argument("-f", "--format", dest = "dataformat", nargs = 1,
    default = "?", type = str, help = "enforced format of the input files (fluoressence, datapoints, ezspec, tableheader)")

    parser.add_argument("-t", "--timerange", dest = "timerange", default = None, type = parse_timerange_arg, 
    help = "time range that should be shown in the chart (e.g. 200,1000 will show 200 seconds before the addition of dithionite and 1000 seconds after the addition of dithionite)")

    parser.add_argument("-c", "--colors", dest = "colors", default = None, type = parse_colors_arg,
    help = "colors to use for the individual data lines (pyplot-supported color names or hexadecimal codes separated by commas)")

    parser.add_argument("-o", "--output", dest = "output_file", type = str, default = "scrambling.png", help = "name of the output file containing the plot")

    return parser.parse_args()


def main():
    args = parse_arguments()

    measurements = Measurements(
                    args.file, 
                    args.dataformat[0].lower() if args.dataformat[0] is not None else None, 
                    args.timerange if args.timerange is not None else (None, None),
                    args.colors if args.colors is not None else [],
                    args.output_file)
    measurements.process()

if __name__ == "__main__":
    main()
EOF
