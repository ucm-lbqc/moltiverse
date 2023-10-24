# moltiverse

Moltiverse is a command-line application for generating molecule conformers.

## Installation

```
shards install
```

## Requirements
External software:
- [OpenBabel](https://openbabel.org)
- [Namd](https://www.ks.uiuc.edu/Research/namd/)
- [Ambertools](https://ambermd.org/AmberTools.php)

## Usage

**NOTE**: This application is still under development and is not ready for production. 
Please note that we have not yet released a version or documentation. But stay tuned, we will do it soon ;).

Check the [data](/data) directory. There you will find a [bash file](/data/run.sh) and an [SMI](/data/molecules.smi) file. The SMI format contains several lines of SMILE code to encode molecules, and an assigned name for that molecule in the right column. You can change this and use whatever you like.
You can access the SMILE codes from [PubChem](https://pubchem.ncbi.nlm.nih.gov/).

This command will run the whole protocol and create a folder for each molecule in the SMI file. Inside each folder you will find the final conformers written in an SDF file.

## Citing

If you use `moltiverse` in your research, please consider citing the
following article:

    To be added


## Contributing

1. Fork it (<https://github.com/your-github-user/moltiverse/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Mauricio Bedoya](https://github.com/your-github-user) - creator and maintainer
