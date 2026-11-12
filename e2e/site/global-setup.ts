import { writeFileSync } from 'node:fs';

export default function globalSetup() {
  writeFileSync('tempos-clique.tsv', 'projeto\tbotao\tms\n');
}
