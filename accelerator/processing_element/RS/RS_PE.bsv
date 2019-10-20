/******************************************************************************
Author: Hyoukjun Kwon (hyoukjun@gatech.edu)

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

*******************************************************************************/

/* Primitives */
import Fifo::*;
import CReg::*;
import Vector::*;

/* Neural network types */
import NeuralNetworkConfig::*;
import NeuralNetworkTypes::*;
import DerivedNeuralNetworkConfig::*;
import RowStationaryPE_Types::*;

/*****************************************************************************
  A row-statinary processing element
  - Receives weights and input feature maps
  - Generate a partial sum after a designated delay (PEDelay)
  - Becomes a realistic PE when you replace the multiplier with a realistic one
******************************************************************************/

(* synthesize *)
module mkRS_ProcessingElement(ProcessingElement);

  /* Input Queues */
  Vector#(PEDelay, Fifo#(PEFifoDepth, Pixel))    weightFifos <- replicateM(mkPipelineFifo);
  Vector#(PEDelay, Fifo#(PEFifoDepth, Pixel)) ifMapFifos  <- replicateM(mkPipelineFifo);
  
  /* Output Queues */
  Fifo#(PEFifoDepth, Pixel) pSumOutFifo   <- mkBypassFifo;

  /* Simulate the computation delay using shifts */
  for(Integer stage = 0; stage <valueOf(PEDelay) -1; stage=stage+1)
  begin
    rule rl_doShiftIfMap(ifMapFifos[stage].notEmpty);
      let ifMap = ifMapFifos[stage].first;
      ifMapFifos[stage].deq;
      ifMapFifos[stage+1].enq(ifMap);
    endrule

    rule rl_doShiftWeight(weightFifos[stage].notEmpty);
      let weight = weightFifos[stage].first;
      weightFifos[stage].deq;
      weightFifos[stage+1].enq(weight);
    endrule
  end

  rule rl_generatePSum(ifMapFifos[valueOf(PEDelay)-1].notEmpty);
    let ifMap = ifMapFifos[valueOf(PEDelay)-1].first;
    let weight = weightFifos[valueOf(PEDelay)-1].first;
    ifMapFifos[valueOf(PEDelay)-1].deq;
    weightFifos[valueOf(PEDelay)-1].deq;

    let res = weight * ifMap;
    pSumOutFifo.enq(res);

    `ifdef DEBUG_RS_PE_WEIGHT
      $display("[RS_PE]Generate a PSum. Deque a weight and an ifMap.");
    `endif
  endrule

  method Action enqWeight(Pixel weight);
    `ifdef DEBUG_RS_PE_WEIGHT
      $display("[RS_PE]Received a Weight");
    `endif
    weightFifos[0].enq(weight);
  endmethod

  method Action enqIfMap(Pixel ifPixel);
    `ifdef DEBUG_RS_PE
      $display("[RS_PE]Received an IfMap");
    `endif
    ifMapFifos[0].enq(ifPixel);
  endmethod

  method ActionValue#(Pixel) deqPSum;
    `ifdef DEBUG_RS_PE
      $display("[RS_PE]Sending a PSum");
    `endif
    pSumOutFifo.deq;
    return pSumOutFifo.first;
  endmethod

endmodule
