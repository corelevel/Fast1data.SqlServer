# Per-file Script Session Contract

**Feature**: [../spec.md](../spec.md) | **Executor interface**: [migration-execution.md](migration-execution.md) | **Research**: [../research.md](../research.md)

FR-016 supersedes the borrowed-command, connection-cloning, and command-restoration parts of the earlier FR-015 design. The required interface is `Invoke-Migration -ConnStr <string> -Script <string>`. This is a requirements update; implementation and new-interface acceptance are pending T056-T058.

## Validation and allocation boundary

Require a nonblank connection string and script path. After explicitly rejecting null/empty/whitespace ConnStr, validate syntax/keywords/typed values locally through SqlConnectionStringBuilder before any zero-batch return. This creates no execution connection/command; retain the original string rather than using the builder's reconstructed value. Do not probe login/reachability for empty scripts. Additional provider validation during executable-path construction/open remains a terminating initialization failure. Reject invalid input without SQL effects or secrets in contextual diagnostics.

Read, preflight, parse, and validate every executable batch span before creating execution resources. Invalid and zero-batch scripts open no execution connection or command; zero-batch files may still receive one history record through the public owner. Preview/declined confirmation retains read-only validation without executor mutation.

## Target and authentication

Use the original caller-supplied ConnStr to initialize a new SqlConnection inside the executor. Open it under the existing owned TransactionScopeOption.Suppress scope, then create an owned SqlCommand with CommandTimeout 0. Target database, authentication, and options come from that string, including its configured/default catalog behavior. Do not derive them from history's current database or an opened connection's potentially redacted ConnectionString.

No caller-created command, open connection, assigned executor transaction, cloned SqlCredential, AccessToken, or token callback is part of this interface. Connection-string authentication modes used by the deployment still require appropriate live validation. History keeps its own command/connection and assigned-transaction support. Creation/open/command failures terminate without falling back to history resources or writing completion.

## Transaction and session boundaries

Keep ambient suppression active through script execution and owned SQL resource disposal, then dispose the scope to restore the caller's ambient context. History's transaction behavior remains unchanged and no phase transaction is added.

Execute all nonempty parser batches once in order through the same owned command/session. Preserve original source slices, use text mode, clear stale parameters, and discard results. Temporary objects/settings survive GO within the file and cannot affect history or the next file. Pooling may reuse physical sessions after reset; observable isolation matters rather than unique SPIDs across files.

After all batches succeed, run the existing read-only SELECT @@TRANCOUNT check on that command with the same unbounded timeout. Require zero outstanding explicit transactions; never commit them automatically. A failed check or nonzero result prevents history. Zero-batch files run no postflight query.

## Owned cleanup and completion

Success requires all batches, the final transaction check, and disposal of every owned resource to succeed. Dispose command, connection, then suppression scope in that order, attempting every disposal even if an earlier one fails. Initialization failure must still release any resource already created. Preserve the first execution error and attach subsequent cleanup failures using the existing generic cleanup helpers. A cleanup-only error terminates after all attempts and prevents history/later scripts.

There is no borrowed executor command to rebind or restore. Never close, dispose, or modify history resources. Contextual diagnostics identify script/stage and batch/source position where relevant, without connection strings, credentials, tokens, full SQL, or parameter values. Preserve underlying exceptions programmatically.

## Public integration and acceptance

Invoke-Fast1Migration forwards its original ConnStr directly to the executor, then calls Set-Executed with its history SqlCmd only after successful executor completion. The history command stays at its configured timeout; remove script/history timeout switching and obsolete clone/binding/restoration seams. The public owner disposes history resources; the executor disposes execution resources.

T056-T058 cover typed ConnStr/no-SqlCmd signatures, no caller-resource prerequisite, original-string forwarding, target/options/authentication, one session per file, ambient suppression, transaction completion, owned command/connection/scope failure cleanup, and source/staged acceptance. Existing clone/restoration results remain historical and do not establish FR-016. Run SQL checks only against the explicitly selected disposable environment; record unrun modes/platforms honestly. See [../quickstart.md](../quickstart.md).
