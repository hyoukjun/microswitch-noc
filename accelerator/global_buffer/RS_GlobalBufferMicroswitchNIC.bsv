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
import Vector::*;
import Fifo::*;
import CReg::*;

/* NoC types */
import MicroswitchTypes::*;
import MicroswitchMessageTypes::*;
import MicroswitchNetworkTypes::*;

/* Neural network types */
import NeuralNetworkConfig::*;
import NeuralNetworkTypes::*;
import GlobalBufferTypes::*;

/* NoC modules */
import MicroswitchController::*;

/* Neural network modules */
import RS_GlobalBuffer::*;

(* synthesize *)
module mkGlobalBufferMicroswitchNIC(GlobalBufferNIC);

  Reg#(Maybe#(GlobalBufferMsg))   currMsg      <- mkReg(Invalid);
  MicroswitchController           msController <- mkMicroswitchController;

  /* I/O Fifos */
  Fifo#(1, Flit)                  flitInFifo   <- mkPipelineFifo;
  Fifo#(1, GlobalBufferMsg)       outMsgFifo   <- mkBypassFifo;

  Fifo#(2, MS_ScatterSetupSignal) controlSignalOutFifo <- mkBypassFifo;
  Fifo#(2, Flit)                  flitOutFifo          <- mkPipelineFifo;

  rule sendFlits(isValid(currMsg)); 
    let msg = validValue(currMsg);

    Flit newFlit = ?;
    newFlit.msgType = msg.dataType;
    newFlit.dests = msg.dests;
    newFlit.flitData = msg.pixelData;

    let controlSignal = msController.getScatterControlSignal(msg.dests);
    controlSignalOutFifo.enq(controlSignal);
    flitOutFifo.enq(newFlit);
    currMsg <= Invalid;
  endrule

  rule do_receiveFlits;
    flitInFifo.deq;
    outMsgFifo.enq(?); 
  endrule

  Vector#(NumBuffer2NetworkPorts, NetworkExternalInterface) ntkPortsDummy;
  for(Integer prt = 0; prt < valueOf(NumBuffer2NetworkPorts); prt = prt+1) begin
    ntkPortsDummy[prt] = 
      interface NetworkExternalInterface
        method Action putFlit(Flit flit);
          `ifdef DEBUG_GLOBALBUFFERNIC
            $display("[GlobalBufferNIC] port[%d]: receiving a flit", prt);
         `endif
          flitInFifo.enq(flit);
        endmethod

        method ActionValue#(Flit) getFlit;
          `ifdef DEBUG_GLOBALBUFFERNIC
            $display("[GlobalBufferNIC] port[%d]: sending a flit", prt);
          `endif
          flitOutFifo.deq;
          let flit = flitOutFifo.first;
          return flit;
        endmethod

      endinterface;
  end
  interface ntkPorts = ntkPortsDummy; 

  interface GlobalBufferPort bufferPort;
    method Action enqMsg(GlobalBufferMsg msg) if(!isValid(currMsg));
      currMsg <= Valid(msg);
    endmethod

    method ActionValue#(GlobalBufferMsg) deqMsg;
      outMsgFifo.deq;
      return outMsgFifo.first;
    endmethod
  endinterface

  method ActionValue#(MS_ScatterSetupSignal) getSetupSignal;
    `ifdef DEBUG_GLOBALBUFFERNIC
     $display("[GlobalBufferNIC] sending a control signal");
    `endif

    controlSignalOutFifo.deq;
    let controlSignal = controlSignalOutFifo.first;
    return controlSignal;
  endmethod

endmodule
