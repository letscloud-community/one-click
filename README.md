# One-Click

This project provides pre-configured Packer templates to create one-click deployable machine images for cloud environments. These images are optimized for quick deployment and include necessary configurations for specific use cases.

## Prerequisites

Before using this project, ensure you have the following installed:

- [Packer](https://www.packer.io/) (>= 1.7.0)
- Access to your cloud provider's API (e.g., API keys or credentials)
- A working terminal environment

## Usage

1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/letscloud-community/one-click.git
   cd one-click

2. Customize the Packer template file (`example.pkr.hcl`) to suit your needs. 
Update variables such as:

`location_slug`: The data center location (e.g., mia1).
`plan_slug`: The server plan (e.g., 1vcpu-1gb-10ssd).
`image_slug`: The base image (e.g., ubuntu-24.04-x86_64).
`snapshot_name`: The name of the snapshot to be created.
`api_key`: Your cloud provider's API key.

Example snippet from a Packer template:
```hcl
variable "api_key" {
  type = string
}

source "letscloud" "one-click" {
  api_key       = var.api_key
  location_slug = "mia1"
  plan_slug     = "1vcpu-1gb-10ssd"
  image_slug    = "ubuntu-24.04-x86_64"
  snapshot_name = "example-snapshot"
}
```

3. Validate the Packer template:
```bash
packer validate example.pkr.hcl
```

4. Set your API key as an environment variable:
```bash
export LETSCLOUD_API_KEY='your-api-key'
```

5. Build the image and set your api key:
```bash
packer build -var "api_key=$LETSCLOUD_API_KEY" example.pkr.hcl
```

This will create a snapshot with the name you set in your hcl file in the location and after that you can sync the snapshot to other locations.

## License
This project is licensed under the MIT License. See the LICENSE file for details.