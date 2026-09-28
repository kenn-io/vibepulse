# Agent instructions

## Namespace runners

Public Namespace runner profiles use **Restricted** access, which [disables workload access to Namespace features and APIs](https://namespace.so/docs/solutions/github-actions/runner-controls/access-levels).
GitHub fork approvals, secrets, and token permissions are separate controls.
Do not infer fork eligibility or network/cache isolation from this setting.
