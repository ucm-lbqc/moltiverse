# Good
../bin/moltiverse -l files/0V5_3UJS_B.mol --keep_hydrogens true  --seed no --water false --metadynamics true --dimension 1 -o test01 --bounds_colvars '0,2,3,0.1,0,2,3,0.1'

# Fails
#../bin/moltiverse -l files/0V5_3UJS_B.pdb --keep_hydrogens true  --seed no --water false --metadynamics true --dimension 1 -o test02 --bounds_colvars '0,2,3,0.1,0,2,3,0.1'

# Good
../bin/moltiverse -l files/0V5_3UJS_B.pdb --keep_hydrogens false  --seed no --water false --metadynamics true --dimension 1 -o test03 --bounds_colvars '0,2,3,0.1,0,2,3,0.1'

# Good
../bin/moltiverse -l files/0V5_3UJS_B.mol --keep_hydrogens false --seed no --water false --metadynamics true --dimension 1 -o test04 --bounds_colvars '0,2,3,0.1,0,2,3,0.1'

# Good
# Fix the Total simulation time
../bin/moltiverse -l files/0V5_3UJS_B.mol --keep_hydrogens false --seed no --water false --metadynamics true --dimension 2 -o test05 --bounds_colvars '0,3,3,0.1,0,2,2,0.1'

# Good
../bin/moltiverse -l files/0V5_3UJS_B.mol --keep_hydrogens true  --seed 1415 --water false --metadynamics true --dimension 1 -o test06 --bounds_colvars '0,2,3,0.1,0,2,2,0.1'
