USING System.Serialization;

NAMESPACE Simatic.Ax.LAcycCom.Procedural
  FUNCTION INTERNAL SerializeParamAddress : UDINT
    VAR_INPUT
      header : LAcycCom_typeParameterHeader;
      address : ARRAY[*] OF LAcycCom_typeParameterAddress;
    END_VAR
    
    VAR_IN_OUT
      buffer : ARRAY[*] of BYTE;
    END_VAR

    VAR_TEMP
      parametersUpperBound : DINT;
      parametersLowerBound : DINT;
      bufferLowerBound : DINT;
      index : DINT;
    END_VAR;

    // read boundaries
    parametersLowerBound := LOWER_BOUND(address, 1);
    parametersUpperBound := UPPER_BOUND(address, 1);
    bufferLowerBound := LOWER_BOUND(buffer, 1);

    // serialize header (refNo, reqId, doId, parameterNo)
    SerializeParamAddress := SerializeBig(offset := TO_UDINT(bufferLowerBound), value := header.refNo, buffer := buffer);
    SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := header.reqId, buffer := buffer);
    SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := header.doId, buffer := buffer);
    SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := header.parameterNo, buffer := buffer);

    // serialize address (attribue, elementNo, parameterNo, index)
    FOR index := parametersLowerBound TO parametersUpperBound DO
      SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := address[index].attribute, buffer := buffer);
      SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := address[index].elementNo, buffer := buffer);
      SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := address[index].parameterNo, buffer := buffer);
      SerializeParamAddress := SerializeBig(offset := SerializeParamAddress, value := address[index].index, buffer := buffer);
    END_FOR;
  END_FUNCTION

  FUNCTION INTERNAL SerializeParamWrite : UDINT
    VAR_INPUT
      header : LAcycCom_typeParameterHeader;
      data : ARRAY[*] OF BYTE;
    END_VAR
    
    VAR_IN_OUT
      buffer : ARRAY[*] of BYTE;
    END_VAR

    VAR_TEMP
      parametersUpperBound : DINT;
      parametersLowerBound : DINT;
      bufferLowerBound : DINT;
      index : DINT;
    END_VAR;

    // read boundaries
    parametersLowerBound := LOWER_BOUND(data, 1);
    parametersUpperBound := UPPER_BOUND(data, 1);
    bufferLowerBound := LOWER_BOUND(buffer, 1);

    // serialize header (refNo, reqId, doId, parameterNo)
    SerializeParamWrite := SerializeBig(offset := TO_UDINT(bufferLowerBound), value := header.refNo, buffer := buffer);
    SerializeParamWrite := SerializeBig(offset := SerializeParamWrite, value := header.reqId, buffer := buffer);
    SerializeParamWrite := SerializeBig(offset := SerializeParamWrite, value := header.doId, buffer := buffer);
    SerializeParamWrite := SerializeBig(offset := SerializeParamWrite, value := header.parameterNo, buffer := buffer);

    // serialize write parameter
    FOR index := parametersLowerBound TO parametersUpperBound DO
      SerializeParamWrite := SerializeBig(offset := SerializeParamWrite, value := data[index], buffer := buffer);
    END_FOR;
  END_FUNCTION

  FUNCTION INTERNAL DeserializeParamResponse : UDINT
    VAR_OUTPUT
      header : LAcycCom_typeParameterHeader;
      response : ARRAY[*] OF BYTE;
      error : BOOL;
    END_VAR

    VAR_IN_OUT
      buffer : ARRAY[*] of BYTE;
    END_VAR

    VAR_TEMP
      responseUpperBound : DINT;
      responseLowerBound : DINT;
      bufferUpperBound : DINT;
      bufferLowerBound : DINT;
      lengthResponse : INT;
      lengthBuffer : INT;
      index : DINT;
    END_VAR
    
    // read boundaries
    responseLowerBound := LOWER_BOUND(response, 1);
    responseUpperBound := UPPER_BOUND(response, 1);
    bufferLowerBound := LOWER_BOUND(buffer, 1);
    bufferUpperBound := UPPER_BOUND(buffer, 1);

    // get length of response
    lengthResponse := TO_INT(GetCountOfElements(responseLowerBound, responseUpperBound));

    // get length of buffer
    lengthBuffer := TO_INT(GetCountOfElements(bufferLowerBound, bufferUpperBound));

    // consider header size
    lengthBuffer := lengthBuffer - 4;

    // check size of receiving buffer (must be atleast as big as response buffer) -> skip deserialization and return with error when its too small
    IF (lengthBuffer < lengthResponse) THEN
      error := TRUE;
      DeserializeParamResponse := UDINT#0;
      RETURN;
    END_IF;

    // deserialize header (refNo, reqId, doId, parameterNo)
    DeserializeParamResponse := DeserializeBig(offset := TO_UDINT(bufferLowerBound), buffer := buffer, value := header.refNo);
    DeserializeParamResponse := DeserializeBig(offset := DeserializeParamResponse, buffer := buffer, value := header.reqId);
    DeserializeParamResponse := DeserializeBig(offset := DeserializeParamResponse, buffer := buffer, value := header.doId);
    DeserializeParamResponse := DeserializeBig(offset := DeserializeParamResponse, buffer := buffer, value := header.parameterNo);

    // deserialize response data
    FOR index := responseLowerBound TO responseUpperBound DO
      // Since the buffer and response is a byte-array, the values after the header can be just directly copied over (no need to deserialize here, could benefit from better performance)
      // DeserializeParamResponse := DeserializeBig(offset := DeserializeParamResponse, buffer := buffer, value := response[index]);
 
      // begin copy of array at previous element after deserializing of header
      // since the values in the buffer from the response are ordered in big endianess the index can be increment by 1 to copy the next byte
      response[index] := buffer[DeserializeParamResponse];
      DeserializeParamResponse := DeserializeParamResponse + UDINT#1;
    END_FOR;
  END_FUNCTION
END_NAMESPACE