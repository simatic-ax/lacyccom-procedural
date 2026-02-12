NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Defines a data structure that is used as a dataset to read/write parameters to a SINAMICS drive object
    LAcycCom_DatatypeSelector : SINT (
      TYPE_REAL := SINT#1,  /// use REAL type
      TYPE_DWORD := SINT#2  /// use DWORD type
      // todo: https://code.siemens.com/axpc/libraries/lacyccom/lib/-/issues/2
      // TYPE_LREAL := SINT#3   /// use LREAL type
    ) := TYPE_REAL;
  END_TYPE  
END_NAMESPACE