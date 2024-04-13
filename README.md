# Moltiverse

[<img align="left" src="./assets/moltiverse_logo_color_hex_transparent.png" width="250" />](./assets/moltiverse_logo_color_hex_transparent.png) Moltiverse is a molecular conformer generator available as an open-source command line application written in the modern Crystal language. 

Moltiverse uses the robust ecosystem of open-source applications to process the molecules and perform conformational sampling. 

The conformer generation protocol consists of seven main steps: (i) molecular pre-processing which includes conversion of the SMILES code into three-dimensional coordinates using Open Babel software, (ii) structure spreading, (iii) parameterization of the molecule with the GAFF2 force field using Amber Tools, (iv) energetic minimization, (v) sampling of the molecule with the M-eABF method in vacuum using the NAMD molecular dynamics engine, (vi) structure clustering, and (vii) conformer ensemble refinement using electronic structure optimization calculations with XTB software. 



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
