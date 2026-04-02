NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains the different modes of a drive object that can be controlled via LAcycCom_DriveComponentsActDeact
        DriveComponentMode : SINT (
            /// component state will not be changed
            NO_CHANGE := SINT#-1,
            /// component will be deactivated
            DEACTIVATE := SINT#0,
            /// component will be activated
            ACTIVATE := SINT#1,
            /// component will be deactivated and is not present
            DEACTIVATE_AND_NOT_PRESENT := SINT#2
        ) := NO_CHANGE;
    END_TYPE
END_NAMESPACE