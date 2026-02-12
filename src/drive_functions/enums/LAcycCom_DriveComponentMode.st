NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Contains the different modes of a drive object that can be controlled via LAcycCom_DriveComponentsActDeact
    LAcycCom_DriveComponentMode : SINT (
      NO_CHANGE := SINT#-1,                 /// component state will not be changed
      DEACTIVATE := SINT#0,                 /// component will be deactivated
      ACTIVATE := SINT#1,                   /// component will be activated
      DEACTIVATE_AND_NOT_PRESENT := SINT#2  /// component will be deactivated and is not present
    ) := NO_CHANGE;
  END_TYPE
END_NAMESPACE