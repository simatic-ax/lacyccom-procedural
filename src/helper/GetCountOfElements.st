NAMESPACE Simatic.Ax.LAcycCom.Procedural
  FUNCTION INTERNAL GetCountOfElements : UDINT
    VAR_INPUT
      lowerBound : DINT;
      upperBound : DINT;
    END_VAR
    
    IF (lowerBound < 0) THEN
      // arr [-1..3] -> 5 elements
      GetCountOfElements := TO_UDINT((lowerBound * -1) + upperBound + 1);
    ELSIF (lowerBound > 0) THEN
      // arr [1..3] -> 3 elements
      GetCountOfElements := TO_UDINT(upperBound - lowerBound + 1);
    ELSE 
      // arr [0..3] -> 4 elements
      GetCountOfElements := TO_UDINT(upperBound + 1);
    END_IF;
  END_FUNCTION
END_NAMESPACE