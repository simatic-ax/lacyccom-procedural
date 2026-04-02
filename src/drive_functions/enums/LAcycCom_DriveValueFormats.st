NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        DriveValueFormats : USINT (
            /// Identifier for Boolean format
            FORMAT_BOOLEAN := USINT#1,
            /// Identifier for Integer8 format
            FORMAT_INTEGER_8 := USINT#2,
            /// Identifier for Integer16 format
            FORMAT_INTEGER_16 := USINT#3,
            /// Identifier for Integer32 format
            FORMAT_INTEGER_32 := USINT#4,
            /// Identifier for Unsigned8 format
            FORMAT_UNSIGNED_8 := USINT#5,
            /// Identifier for Unsigned16 format
            FORMAT_UNSIGNED_16 := USINT#6,
            /// Identifier for Unsigned32 format
            FORMAT_UNSIGNED_32 := USINT#7,
            /// Identifier for Floating Point32 format
            FORMAT_FLOATING_POINT := USINT#8,
            /// Identifier for OctetString format
            FORMAT_OCTET_STRING := USINT#10,
            /// Identifier for TimeDifference format
            FORMAT_TIME_DIFFERENCE := USINT#13,
            /// Identifier for FloatingPoint64 format
            FORMAT_FLOATING_POINT_64 := USINT#15,
            /// Identifier for TimeDifference without date indication format
            FORMAT_TIME_DIFFERENCE_WO_DATE := USINT#54,
            /// Identifier for void telegram
            FORMAT_ZERO := USINT#64,
            /// Identifier for Byte format
            FORMAT_BYTE := USINT#65,
            /// Identifier for Word format
            FORMAT_WORD := USINT#66,
            /// Identifier for Double Word format
            FORMAT_DOUBLE_WORD := USINT#67,
            /// Identifier for a format error
            FORMAT_ERROR := USINT#68
        );
    END_TYPE
END_NAMESPACE