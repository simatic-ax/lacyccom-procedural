NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE INTERNAL
    LAcycCom_DriveValueFormats : SINT (
      FORMAT_INTEGER_8 := SINT#2,   // Identifier for Integer8 format
      FORMAT_INTEGER_16 := SINT#3,   // Identifier for Integer16 format
      FORMAT_INTEGER_32 := SINT#4,   // Identifier for Integer32 format
      FORMAT_UNSIGNED_8 := SINT#5,   // Identifier for Unsigned8 format
      FORMAT_UNSIGNED_16 := SINT#6,   // Identifier for Unsigned16 format
      FORMAT_UNSIGNED_32 := SINT#7,   // Identifier for Unsigned32 format
      FORMAT_FLOATING_POINT := SINT#8,   // Identifier for Floating Point format
      FORMAT_OCTET_STRING := SINT#10,   // Identifier for OctetString format
      FORMAT_TIME_DIFFERENCE := SINT#13,   // Identifier for TimeDifference format
      FORMAT_TIME_DIFFERENCE_WO_DATE := SINT#54,   // Identifier for TimeDifference without date indication format
      FORMAT_ZERO := SINT#64,   // Identifier for void telegram
      FORMAT_BYTE := SINT#65,   // Identifier for Byte format
      FORMAT_WORD := SINT#66,   // Identifier for Word format
      FORMAT_DOUBLE_WORD := SINT#67,   // Identifier for Double Word format
      FORMAT_ERROR := SINT#68   // Identifier for a format error
    );
  END_TYPE
END_NAMESPACE