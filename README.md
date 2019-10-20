NOCS2017 "Rethinking NoCs for Spatial Neural Network Accelerators" codebase
(Paper is available in the following link; http://synergy.ece.gatech.edu/wp-content/uploads/sites/332/2017/08/MicroSwitch_NOCS2017.pdf)

- Code license (MIT license)

Copyright (c) 2017 Georgia Instititue of Technology

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

- How to change user parameters
    You can modify parameters in NeuralNetworkConfig.bsv
    
    * Parameter description
      - PixelBitSz: Input/weight bit size
      - NumPERows, NumPEColumns: to modify the number of PEs. 
        + You need to make the number of PEs to be the power of 2 to get microswitch network work
        + For RS traffic, NumPEColumns should be greater or equal than the FilterSz.
      - PEdelay: the delay of each PE
      - NumChannels, NuMFilters, NumIfMaps, FilterSz, IfMapSz, Stride: Defines the dimension of the target convolution layer to simulate.
        + Please note that it is necessary information for reconfiguration controller and the traffic generator.
        + To run another layer, you need to modify the parameter and compile the simulation again.

- How to run the compilation
    ./microswitch -ms     : compile a simulation with Weight-stationary traffic
    ./microswitch -rms    : compile a simulation with Row-strationary traffic
    ./microswitch -rmv    : generate Verilog RTL in ./MSVerilog/
    ./microswitch -clean  : clean up build files
    ./microswitch -r      : run a complied simulation

  * To run the compiler and simulation, you need Bluespec System Verilog (www.bluespec.com) compiler
