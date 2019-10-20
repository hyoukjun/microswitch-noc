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

import Vector::*;
import Fifo::*;
import CReg::*;

/* NoC Types */
import MicroswitchTypes::*;
import MicroswitchMessageTypes::*;

/* Neural network types */
import NeuralNetworkConfig::*;
import NeuralNetworkTypes::*;
import DerivedNeuralNetworkConfig::*;
import GlobalBufferTypes::*;
import RowStationaryPE_Types::*;

// Weight Destination Calculation
function DestBits getWeightDest(Data numSentWeights, Data activeColumns);
  DestBits ret = 0;
  for(Integer c = 0; c < valueOf(NumPEColumns); c=c+1) 
  begin
    if(fromInteger(c) < activeColumns) //Folding
      ret[numSentWeights * fromInteger(valueOf(NumPEColumns)) + fromInteger(c)] = 1;
  end 
  return ret;
endfunction

function DestBits getIfMapDest(Data numSentIfMaps, Data activeColumns);
  DestBits ret = 0;
  for(Data r=0; r<fromInteger(valueOf(NumPERows)); r=r+1) 
  begin
    if(numSentIfMaps - r >= 0 && numSentIfMaps -r < fromInteger(valueOf(NumPEColumns))) begin
      if(numSentIfMaps - r  < activeColumns) begin //Folding
        ret[ r * fromInteger(valueOf(NumPEColumns)) + numSentIfMaps -r] = 1;
      end
    end
  end
  return ret;

endfunction

(* synthesize *)
module mkRS_GlobalBuffer(GlobalBuffer);

  /* States */
  Reg#(Bool)              inited        <- mkReg(False);
  Reg#(Bool)              isFinishedReg <- mkReg(False);
  Reg#(GlobalBufferState) bufferState   <- mkReg(Idle);

  /* Counters */
  Reg#(Data)     weightSendCount      <- mkReg(0);
  Reg#(Data)     ifMapSendCount       <- mkReg(0);
  CReg#(2, Data) pSumRecvCount        <- mkCReg(0);
  Reg#(Data)     columnIterationCount <- mkReg(0);

  CReg#(3, Data) iterationCredit <- mkCReg(fromInteger(valueOf(PEFifoDepth))-1);
  Reg#(Data) totalPSumRecvCount  <- mkReg(0);

  /* Fifos */
  Fifo#(1, GlobalBufferMsg) msgOutFifo       <- mkBypassFifo;
  Fifo#(PEFifoDepth, Data)  numPSumstoGather <- mkPipelineFifo;
  Fifo#(1, Data)            numActiveColumns <- mkPipelineFifo;

  function Action updateColumnIterationCount;
  action
    if(columnIterationCount < fromInteger(valueOf(NumNormalColumnIteration))-1) begin
      columnIterationCount <= columnIterationCount + 1;
    end
    else begin
      columnIterationCount <= 0;
    end
  endaction
  endfunction

  function Bool hasCredit = (iterationCredit[1] > 0);

  function Action decCredit;
  action
    `ifdef DEBUG_GLOBALBUFFER
      $display("[GlobalBuffer] Decrease Credit", iterationCredit[1], iterationCredit[1]-1);
    `endif
    iterationCredit[1] <= iterationCredit[1] -1;
  endaction
  endfunction

  function Action incCredit;
  action
    `ifdef DEBUG_GLOBALBUFFER
      $display("[GlobalBuffer] Increase Credit", iterationCredit[0], iterationCredit[0]+1);
    `endif
    iterationCredit[0] <= iterationCredit[0] +1;
  endaction
  endfunction

  function Action changeState(GlobalBufferState newState);
  action
    bufferState <= newState;
  endaction
  endfunction

  function Action updateNumActiveColumns;
  action
    let fullIterSz = fromInteger(valueOf(NumPEColumns));
    let residueIterSz = fromInteger(valueOf(OfMapSz) % valueOf(NumPEColumns));

    //Case1: Normal case
    if(columnIterationCount < fromInteger(valueOf(NumNormalColumnIteration))) begin
      numActiveColumns.enq(fullIterSz);
    end
    //Case2: At the end of iteration for a row.
    else begin
      numActiveColumns.enq(residueIterSz);
    end

  endaction
  endfunction

  function Action updatePSumstoGather;
  action
    let fullIterSz = fromInteger(valueOf(NumPEColumns));
    let residueIterSz = fromInteger(valueOf(OfMapSz) % valueOf(NumPEColumns));

    //Case1: Normal case
    if(columnIterationCount < fromInteger(valueOf(NumNormalColumnIteration))-1) begin
        numPSumstoGather.enq(fullIterSz); 
    end
    //Case2: At the end of iteration for a row.
    else begin
      numPSumstoGather.enq(residueIterSz);
    end

  endaction
  endfunction

  rule doInit(!inited);
    let fullIterSz = fromInteger(valueOf(NumPEColumns));
    let residueIterSz = fromInteger(valueOf(OfMapSz) % valueOf(NumPEColumns));
    let numFoldings = fromInteger(valueOf(OfMapSz) / valueOf(NumPEColumns));

    inited <= True;

    if(numFoldings > 0) begin
      numActiveColumns.enq(fullIterSz);
    end
    else begin
      numActiveColumns.enq(residueIterSz);
    end

    changeState(WeightSend);
  endrule

  rule prepareNextIteration(bufferState == Idle && inited);
    updateNumActiveColumns();
    changeState(WeightSend);
  endrule

  rule sendWeights(bufferState == WeightSend);
    //Get destination bits
    let dest = getWeightDest(weightSendCount, numActiveColumns.first);
    `ifdef DEBUG_GLOBALBUFFER
      $display("[GlobalBuffer]: GetWeightMapDest(%d, %d) = %b", weightSendCount, numActiveColumns.first, dest);
    `endif

    //Construct a message
    let newGlobalBufferMsg = 
      GlobalBufferMsg{
        msgType: Multicast, 
        dataType: Weight,
        dests: dest,
        pixelData: ?
      };

    //Control logics
    if(weightSendCount >= fromInteger(valueOf(NumPERows))-1) begin
      weightSendCount <= 0;
      changeState(IfMapSend);

      //Determine the number of partial sums to gather in this iteration
      //This manages the column folding
      updatePSumstoGather();

      updateColumnIterationCount();
    end
    else begin
      weightSendCount <= weightSendCount + 1;
    end
    
    //Send the message
    msgOutFifo.enq(newGlobalBufferMsg);

  endrule

  rule sendIfMaps(bufferState == IfMapSend);
    //Get destination bits
    let dest = getIfMapDest(ifMapSendCount, numActiveColumns.first);
    `ifdef DEBUG_GLOBALBUFFER
      $display("[GlobalBuffer]: GetIfMapDest(%d, %d) = %b", ifMapSendCount, numActiveColumns.first, dest);
    `endif

    //Construct a message
    let newGlobalBufferMsg = 
      GlobalBufferMsg{
        msgType: Multicast, 
        dataType: IfMap,
        dests: dest,
        pixelData: ?
      };

    if(ifMapSendCount == fromInteger(valueOf(NumPERows) + valueOf(NumPEColumns)) -2) begin
      ifMapSendCount <= 0;
      if(hasCredit()) begin 
        decCredit();
        numActiveColumns.deq;
        changeState(Idle);
      end
      else begin //Not enough credit
        changeState(PSumGather);
      end
    end
    else begin
      ifMapSendCount <= ifMapSendCount + 1;
    end

    //Send the message
    msgOutFifo.enq(newGlobalBufferMsg);

  endrule

  //Wait until the global buffer gets a credit
  rule gatherPSums(bufferState == PSumGather);
    if(hasCredit()) begin
      decCredit();
      numActiveColumns.deq;
      changeState(Idle);
    end
  endrule

  rule checkIteration;
    if(pSumRecvCount[1] >= numPSumstoGather.first) begin
      numPSumstoGather.deq;
      incCredit();
      pSumRecvCount[1] <= pSumRecvCount[1] - numPSumstoGather.first;
    end
  endrule

  rule checkFinish(totalPSumRecvCount == fromInteger(valueOf(NumPSumsRS)));
    isFinishedReg <= True;
  endrule

  interface GlobalBufferPort bufferPort;
    method Action enqMsg(GlobalBufferMsg msg);
      `ifdef DEBUG_GLOBALBUFFER
        $display("[GlobalBuffer]: Received a PSUM. (CurrentPSum: %d, TotalPSum: %d / %d)", pSumRecvCount[0] +1, totalPSumRecvCount+1, valueOf(NumPSumsRS));
      `endif
      pSumRecvCount[0] <= pSumRecvCount[0] + 1;
      totalPSumRecvCount <= totalPSumRecvCount + 1;
    endmethod

    method ActionValue#(GlobalBufferMsg) deqMsg;
      `ifdef DEBUG_GLOBALBUFFER
        $display("[GlobalBuffer]: Sending a message");
      `endif
      let flit = msgOutFifo.first;
      msgOutFifo.deq;
      return flit;
    endmethod
  endinterface

  method Bool isFinished;
    return isFinishedReg;
  endmethod

endmodule
