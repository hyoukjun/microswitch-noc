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

/* NoC types */
import MicroswitchTypes::*;
import MicroswitchMessageTypes::*;
import MicroswitchNetworkTypes::*;

/* Neural network types */
import NeuralNetworkTypes::*;
import NeuralNetworkConfig::*;
import GlobalBufferTypes::*;
import RowStationaryPE_Types::*;

/* Neural network modules */
import RS_PE::*;

/*****************************************************************************
  A network interface for row-statinary processing elements and a microswitch NoC
  - Receives PE messages and generates corresponding microswitch flits
******************************************************************************/

(* synthesize *)
module mkRS_MicroswitchNIC(ProcessingElementNIC);
  Reg#(Bool)  inited <- mkReg(False);

  Reg#(RowID) rID    <- mkRegU;
  Reg#(ColID) cID    <- mkRegU;
  Reg#(Data)  peID   <- mkRegU;

  Reg#(Data)     numPSums    <- mkReg(0);
  Fifo#(1, Bool) decNumPSums <- mkBypassFifo;

  /* I/O Fifos */
  Fifo#(1, Pixel)           weightInFifo  <- mkBypassFifo;
  Fifo#(1, Pixel)           ifMapInFifo   <- mkBypassFifo;
  Fifo#(PEFifoDepth, Pixel) pSumInFifo    <- mkPipelineFifo;

  Fifo#(1, Pixel)           generatedPSum <- mkBypassFifo;

  Fifo#(1, Flit)            flitOutFifo   <- mkBypassFifo;

  rule rl_getPSum(inited);
    Maybe#(Pixel) pSum = Invalid;
    Bool isLocal = False;
    //Prioritize local partial sums
    if(pSumInFifo.notEmpty) begin
      pSum = Valid(pSumInFifo.first);
      pSumInFifo.deq;
      isLocal = True;
    end
    else if(generatedPSum.notEmpty) begin
      pSum = Valid(generatedPSum.first);
      generatedPSum.deq;
    end

    DestBits nullDest = 0;
    DestBits dest2GlobalBuffer = 0;
    dest2GlobalBuffer[valueOf(NumPEs)] = 1;

    if(isValid(pSum)) begin
      let pSumValue = validValue(pSum);
      //Case 1: Local partial sum & send to another PE  
      if(peID > fromInteger(valueOf(NumPEColumns))-1) begin
        NumPEsBit localTarget = truncate(peID - fromInteger(valueOf(NumPEColumns)));
        `ifdef DEBUG_RS_MSNIC
          $display("[RS_MSNIC] Send a partial sum from (%d, %d) to (%d, %d) (localTarget: %d -> %d). NumPSums = %d",rID, cID, rID-1, cID,  peID, localTarget, numPSums);
        `endif
        flitOutFifo.enq(Flit{msgType: PSum, dests: nullDest, localDest: localTarget, flitData: pSumValue});
      end
      //Case 2: Local partial sum & send to global Buffer
      else if(isLocal && numPSums == fromInteger(valueOf(NumPERows)-1)) begin

        `ifdef DEBUG_RS_MSNIC
        $display("[RS_MSNIC] Send a partial sum to globalbuffer from (%d, %d). NumPSums = %d",rID, cID, numPSums);
        `endif
        decNumPSums.enq(True);
        flitOutFifo.enq(Flit{msgType: PSum, dests: dest2GlobalBuffer, localDest:?, flitData: pSumValue});
      end
    end
  endrule

  method Action initialize(RowID init_rID, ColID init_cID);
    inited <= True;
    rID <= init_rID;
    cID <= init_cID;
    peID <= zeroExtend(init_rID) * fromInteger(valueOf(NumPEColumns)) + zeroExtend(init_cID);
  endmethod

  method ActionValue#(Pixel) getWeight;
    weightInFifo.deq;
    return weightInFifo.first;
  endmethod

  method ActionValue#(Pixel) getIfMap;
    ifMapInFifo.deq;
    return ifMapInFifo.first;
  endmethod

  method Action putPSum(Pixel pSum);
    generatedPSum.enq(pSum);
  endmethod

  method Action enqFlit(Flit flit);

    if(flit.dests[peID] == 1 || flit.dests == 0) begin
      case(flit.msgType)
        Weight: begin 
          weightInFifo.enq(flit.flitData);
         `ifdef DEBUG_RS_MSNIC
           $display("[RS_MSNIC] Received a Weight in (%d, %d)", rID, cID);
         `endif
        end
        IfMap: begin
          ifMapInFifo.enq(flit.flitData);
          `ifdef DEBUG_RS_MSNIC
            $display("[RS_MSNIC] Received an IfMap in (%d, %d)", rID, cID);
          `endif
        end
        PSum: begin
          if(rID == 0) begin
            if(decNumPSums.notEmpty) begin
              decNumPSums.deq;
              numPSums <= numPSums + 1 - (fromInteger(valueOf(NumPERows))-1) ;
            end
            else begin
              numPSums <= numPSums + 1;
            end 
          end
          pSumInFifo.enq(flit.flitData);
          `ifdef DEBUG_RS_MSNIC
            $display("[RS_MSNIC] Received a PartialSum in (%d, %d) numPSums = %d", rID, cID, numPSums);
          `endif
        end
        default: begin 
         `ifdef DEBUG_RS_MSNIC
           $display("[RS_MSNIC] Received an unknown flit in (%d, %d)", rID, cID);
         `endif
        end 
      endcase
    end
    `ifdef DEBUG_RS_MSNIC
    else begin
      $display("[RS_MSNIC] Received an invalid flit in (%d, %d)", rID, cID);
      $display("Flit dest: %b, peID: %d", flit.dests, peID);
      for(Integer i=0; i<valueOf(NumPEs)+1; i=i+1) begin
        $display("destBit[%d] = %b", i, flit.dests[i]);
      end
    end
    `endif

  endmethod

  method ActionValue#(Flit) deqFlit if(flitOutFifo.notEmpty);
    let outFlit = flitOutFifo.first;
    flitOutFifo.deq;

    `ifdef DEBUG_RS_MSNIC
      case(outFlit.msgType)
        Weight: begin 
          $display("[RS_MSNIC] Send a Weight in (%d, %d)", rID, cID);
        end
        IfMap: begin
          $display("[RS_MSNIC] Send an IfMap in (%d, %d)", rID, cID);
        end
        PSum: begin
          $display("[RS_MSNIC] Send a PartialSum in (%d, %d)", rID, cID);
        end
      endcase
    `endif

    return outFlit;
  endmethod

endmodule
