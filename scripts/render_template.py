#!/usr/bin/env python3
import jinja2
import yaml
import argparse
from glob import glob
from os import path

def retrieve_config(config_file):
    if path.exists(config_file):
        full_path = path.realpath(config_file)
        with open(full_path, 'r') as file:
            config_data = yaml.safe_load(file)
        return config_data
    else:
        raise FileNotFoundError(f"Unable to find config file at: {config_file}")

def render_templates(directory, config):
    if path.exists(directory):
        directory = path.realpath(directory)
        template_files = glob(f"{directory}/*.jinja")
        for template in template_files:
            file_name = template.split("/")[-1].split('.')[0]
            template_loader = jinja2.FileSystemLoader(f"{directory}")
            environment = jinja2.Environment(loader=template_loader)
            template_file = environment.get_template(f"{file_name}.yaml.jinja")

            with open(f"{directory}/{file_name}.yaml", 'w') as output:
                output.write(template_file.render(**config))
    else:
        raise FileNotFoundError(f"Unable to find manifest directory at: {directory}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-d', '--directory', help='Manifest directory to render templates')
    parser.add_argument('-c', '--config', help="Config file path of variables for rendering manifests in yaml format")
    args = parser.parse_args()

    config_file = retrieve_config(args.config)
    render_templates(args.directory, config_file)
