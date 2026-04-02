NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Defines a data structure that is used as a dataset to read/write parameters to a SINAMICS drive object
        DatatypeSelector : SINT (
            /// use REAL type
            TYPE_REAL := SINT#1,
            /// use DWORD type
            TYPE_DWORD := SINT#2,
            /// use LREAL type
            TYPE_LREAL := SINT#3
        ) := TYPE_REAL;
    END_TYPE  
END_NAMESPACE