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
import WeightStationaryPE_Types::*;

/*****************************************************************************
  A weight-statinary processing element
  - Receives weights and input feature maps
  - Generate a partial sum after a designated delay (PEDelay)
  - Becomes a realistic PE when you replace the multiplier with a realistic one
******************************************************************************/

(* synthesize *)
module mkWS_ProcessingElement(ProcessingElement);

  /* Input Queues */
  Fifo#(WeightFifoDepth, Pixel)  weightFifo <- mkPipelineFifo;

  Vector#(PEDelay, Fifo#(IfMapFifoDepth, Pixel)) ifMapFifos<- replicateM(mkPipelineFifo);

  /* Output Queues */
  Fifo#(PSumFifoDepth, Pixel)    pSumFifo   <- mkBypassFifo;

  CReg#(2, NumPixelsBit) ifMapCount     <- mkCReg(0);


  for(Integer stage = 0; stage <valueOf(PEDelay) -1; stage=stage+1)
  begin
    rule rl_doShift(ifMapFifos[stage].notEmpty);
      let pixel = ifMapFifos[stage].first;
      ifMapFifos[stage].deq;
      ifMapFifos[stage+1].enq(pixel);
    endrule
  end

  rule rl_doSendPSum(ifMapFifos[valueOf(PEDelay)-1].notEmpty);
    let pixel = ifMapFifos[valueOf(PEDelay)-1].first;
    ifMapFifos[valueOf(PEDelay)-1].deq;
    ifMapCount[0] <= ifMapCount[0] + 1;

      let res = zeroExtend(weightFifo.first) * pixel; //Multiplication
      pSumFifo.enq(res); //Generate results

     if(ifMapCount[1] >= fromInteger(valueOf(NumIfMapPixels)) ) begin
     `ifdef DEBUG_WS_PE_WEIGHT
       $display("[WS_PE]Deque a weight");
     `endif
        ifMapCount[1] <= 0;
        weightFifo.deq;
      end

  endrule

  method Action enqWeight(Pixel weight);
    `ifdef DEBUG_WS_PE_WEIGHT
      $display("[WS_PE]Received a Weight");
    `endif
    weightFifo.enq(weight);
  endmethod

  method Action enqIfMap(Pixel ifPixel);
    `ifdef DEBUG_WS_PE
      $display("[WS_PE]Received an IfMap");
    `endif
    ifMapFifos[0].enq(ifPixel);
  endmethod

  method ActionValue#(Pixel) deqPSum;
    `ifdef DEBUG_WS_PE
      $display("[WS_PE]Sending a PSum");
    `endif
    pSumFifo.deq;
    return pSumFifo.first;
  endmethod

  method Action enqPSum(Pixel pSum);
    `ifdef DEBUG_WS_PE
      $display("[WS_PE]Received an IfMap");
    `endif
    noAction;
  endmethod


endmodule
