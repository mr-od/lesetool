export var UserIntegrityCheckFlag;
(function (UserIntegrityCheckFlag) {
    UserIntegrityCheckFlag[UserIntegrityCheckFlag["None"] = 0] = "None";
    /** Check if the number of remaining admin users is greater than 0 */
    UserIntegrityCheckFlag[UserIntegrityCheckFlag["RemainingAdmins"] = 1] = "RemainingAdmins";
    /** Check if the number of users is within the limits */
    UserIntegrityCheckFlag[UserIntegrityCheckFlag["UserLimits"] = 2] = "UserLimits";
    UserIntegrityCheckFlag[UserIntegrityCheckFlag["All"] = 3] = "All";
})(UserIntegrityCheckFlag || (UserIntegrityCheckFlag = {}));
