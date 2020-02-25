# quickstart-microsoft-sql
## SQL Server on AWS with Windows Server Failover Clustering and Always On Availability Groups

AWS provides a comprehensive set of services and tools for deploying Microsoft Windows-based workloads on its highly reliable and secure cloud infrastructure. This Quick Start implements a high availability solution built with Windows Server and SQL Server running on Amazon EC2, using the Always On availability groups feature of SQL Server Enterprise edition.

The deployment includes Windows Server Failover Clustering (WSFC) and clustered SQL Server 2016, 2017, or 2019 instances on the AWS Cloud. The Quick Start includes a rich set of configuration options for SQL Server, Active Directory, and the WSFC cluster, including SQL Server version and licensing, tenancy options, and a choice of two Active Directory implementations: You can use AWS Directory Service for Active Directory, or manage the EC2 instances for Active Directory yourself.

The AWS CloudFormation templates included with the Quick Start automate the following:

- Deploying SQL Server into a new VPC
- Deploying SQL Server into your existing AWS and Active Directory infrastructure

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for SQL Server on AWS](https://d0.awsstatic.com/partner-network/QuickStart/datasheets/sql-server-on-aws-architecture-default.png)

For architectural details, best practices, step-by-step instructions, and customization options, see the [deployment guide](https://fwd.aws/GRNKR).

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/).
