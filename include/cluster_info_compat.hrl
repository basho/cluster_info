-ifndef(CLUSTER_INFO_COMPAT_HRL).

-ifdef(OTP_RELEASE). %% this implies OTP 2-1 or higher
-define(COMPAT_CATCH(Class, Reason, Stacktrace), Class:Reason:Stacktrace).
-define(COMPAT_GET_STACKTRACE(Stacktrace), Stacktrace).
-else.
-define(COMPAT_CATCH(Class, Reason, _), Class:Reason).
-define(COMPAT_GET_STACKTRACE(_), erlang:get_stacktrace()).
-endif.

-define(CLUSTER_INFO_COMPAT_HRL, 1).

-endif.
