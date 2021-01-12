version 1.0

struct InputGroup {
  File fastqR1
  File fastqR2
  String readGroup
}

workflow fusionCalling {

  input {
    Array[InputGroup] inputGroups
    String outputFileNamePrefix
    File? structuralVariants
  }

  scatter (ig in inputGroups) {
    File read1s       = ig.fastqR1
    File read2s       = ig.fastqR2
    String readGroups = ig.readGroup
  }

  parameter_meta {
    inputGroups: "Array of fastq files to align with STAR and the merged filename"
    outputFileNamePrefix: "Prefix for filename"
    structuralVariants: "path to structural variants for sample"
  }

  call align {
    input:
     read1s = read1s,
     read2s = read2s,
     readGroups = readGroups,
     outputFileNamePrefix = outputFileNamePrefix }

  call runArriba {
   input:
    tumorBam = align.sortAlignBam,
    outputFileNamePrefix = outputFileNamePrefix,
    structuralVariants = structuralVariants }

  call runStarFusion {
   input:
    tumorBam = align.sortAlignBam,
    chimericOutJunction  = align.spliceJunctions,
    outputFileNamePrefix = outputFileNamePrefix }

  output {
    File spliceJunctions        = align.spliceJunctions
    File sortAlignBam           = align.sortAlignBam
    File sortAlignIndex         = align.sortAlignIndex
    File fusionsPredictions     = runArriba.fusionPredictions
    File fusionDiscarded        = runArriba.fusionDiscarded
    File fusionFigure           = runArriba.fusionFigure
    File fusions                = runStarFusion.fusionPredictions
    File fusionsAbridged        = runStarFusion.fusionPredictionsAbridged
    File fusionCodingEffects    = runStarFusion.fusionCodingEffects
  }

  meta {
    author: "Alexander Fortuna"
    email: "alexander.fortuna@oicr.on.ca"
    description: "Workflow that takes the Bam output from STAR and detects RNA-seq fusion events."
    dependencies: [
     {
       name: "arriba/2.0",
       url: "https://github.com/suhrig/arriba"
     },
     {
       name: "star/2.7.6a",
       url: "https://github.com/alexdobin/STAR"
     },
     {
       name: "samtools/1.9",
       url: "http://www.htslib.org/"
     },
     {
       name: "star-fusion-genome/1.8.1-hg38",
       url: "https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/__genome_libs_StarFv1.8"
     },
     {
      name: "star-fusion/1.8.1",
      url: "https://github.com/STAR-Fusion/STAR-Fusion/wiki"
    }
   ]
  }
}

task align {
  input {
    Array[File]+ read1s
    Array[File]+ read2s
    Array[String]+ readGroups
    File?  structuralVariants
    String index = "$HG38_STAR_INDEX100_ROOT"
    String modules = "hg38-star-index100/2.7.6a samtools/1.9 star/2.7.6a"
    String chimOutType = "WithinBAM HardClip"
    String outputFileNamePrefix
    Int outFilterMultimapNmax = 1
    Int outFilterMismatchNmax = 3
    Int chimSegmentMin = 10
    Int chimScoreMin = 1
    Int chimScoreDropMax = 30
    Int chimJunctionOverhangMin = 10
    Int chimScoreJunctionNonGTAG = 0
    Int chimScoreSeparation = 1
    Int chimSegmentReadGapMax = 3
    Int chimMultimapNmax = 50
    Int threads = 8
    Int jobMemory = 64
    Int timeout = 72
  }

  parameter_meta {
    read1s: "array of read1s"
    read2s: "array of read2s"
    readGroups: "array of readgroup lines"
    outputFileNamePrefix: "Prefix for filename"
    index: "Path to STAR index"
    modules: "Names and versions of modules to load"
    outFilterMultimapNmax: "max number of multiple alignments allowed for a read"
    outFilterMismatchNmax: "maximum number of mismatches per pair"
    chimSegmentMin: "the minimum mapped length of the two segments of a chimera"
    chimScoreMin: "minimum total (summed) score of the chimeric segments"
    chimScoreDropMax: "max drop (difference) of chimeric score from the read length"
    chimJunctionOverhangMin: "minimum overhang for a chimeric junction"
    chimScoreJunctionNonGTAG: "penalty for a non-GT/AG chimeric junction"
    chimScoreSeparation: "minimum difference between the best chimeric score"
    chimSegmentReadGapMax: "maximum gap in the read sequence between chimeric segments"
    chimOutType: "Where to report chimeric reads"
    threads: "Requested CPU threads"
    jobMemory: "Memory allocated for this job"
    timeout: "Hours before task timeout"
  }

  command <<<
      set -euo pipefail

      STAR \
      --readFilesIn ~{sep="," read1s} ~{sep="," read2s} \
      --outSAMattrRGline ~{sep=" , " readGroups} \
      --readFilesCommand zcat \
      --runThreadN ~{threads} \
      --genomeDir ~{index} --genomeLoad NoSharedMemory \
      --outSAMtype BAM SortedByCoordinate \
      --outSAMunmapped Within --outBAMsortingThreadN ~{threads} \
      --outFilterMultimapNmax ~{outFilterMultimapNmax} \
      --outFilterMismatchNmax ~{outFilterMismatchNmax} \
      --chimSegmentMin ~{chimSegmentMin} --chimOutType ~{chimOutType} \
      --chimJunctionOverhangMin ~{chimJunctionOverhangMin} \
      --chimScoreMin ~{chimScoreMin} --chimScoreDropMax ~{chimScoreDropMax} --chimMultimapNmax ~{chimMultimapNmax} \
      --chimScoreJunctionNonGTAG ~{chimScoreJunctionNonGTAG} --chimScoreSeparation ~{chimScoreSeparation} \
      --alignSJstitchMismatchNmax 5 -1 5 5 \
      --alignSplicedMateMapLminOverLmate 0.5 \
      --chimSegmentReadGapMax ~{chimSegmentReadGapMax} --outFileNamePrefix ~{outputFileNamePrefix}.

  >>>

  runtime {
    memory:  "~{jobMemory} GB"
    modules: "~{modules}"
    cpu:     "~{threads}"
    timeout: "~{timeout}"
  }

  output {
      File spliceJunctions          = "~{outputFileNamePrefix}.SJ.out.tab"
      File sortAlignBam             = "~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam"
      File sortAlignIndex           = "~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam.bai"
  }

  meta {
    output_meta: {
      spliceJunctions: "Splice junctions from star fusion run",
      sortAlignBam: "Output sorted bam file aligned to genome",
      sortAlignIndex: "Output index file for sorted bam aligned to genome",
    }
  }
}

task runArriba {
  input {
    File?  structuralVariants
    String modules = "arriba/2.0 rarriba/0.1 hg38-cosmic-fusion/v91"
    String gencode = "$GENCODE_ROOT/gencode.v31.annotation.gtf"
    String genome = "$HG38_ROOT/hg38_random.fa"
    String cosmic = "$HG38_COSMIC_FUSION_ROOT/CosmicFusionExport.tsv"
    String knownfusions = "$ARRIBA_ROOT/share/database/known_fusions_hg38_GRCh38_v2.0.0.tsv.gz"
    String cytobands = "$ARRIBA_ROOT/share/database/cytobands_hg38_GRCh38_v2.0.0.tsv"
    String domains = "$ARRIBA_ROOT/share/database/protein_domains_hg38_GRCh38_v2.0.0.gff3"
    String blacklist = "$ARRIBA_ROOT/share/database/blacklist_hg38_GRCh38_v2.0.0.tsv.gz"
    String draw = "$ARRIBA_ROOT/bin/draw_fusions.R"
    String outputFileNamePrefix
    Int threads = 8
    Int jobMemory = 64
    Int timeout = 72
  }

  parameter_meta {
    structuralVariants: "file containing structural variant calls"
    outputFileNamePrefix: "Prefix for filename"
    index: "Path to STAR index"
    draw: "path to arriba draw command"
    modules: "Names and versions of modules to load"
    gencode: "Path to gencode annotation file"
    domains: "protein domains for annotation"
    cytobands: "cytobands for figure annotation"
    cosmic: "known fusions from cosmic"
    knownfusions: "known fusions from arriba"
    blacklist: "List of fusions which are seen in normal tissue or artefacts"
    genome: "Path to loaded genome"
    threads: "Requested CPU threads"
    jobMemory: "Memory allocated for this job"
    timeout: "Hours before task timeout"
  }

  command <<<
      set -euo pipefail

      arriba \
      -x ~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam \
      -o ~{outputFileNamePrefix}.fusions.tsv -O ~{outputFileNamePrefix}.fusions.discarded.tsv \
      ~{"-d " + structuralVariants} -k ~{cosmic} \
      -a ~{genome} -g ~{gencode} -b ~{blacklist} -t ~{knownfusions} \
      -T -P

      Rscript ~{draw} --annotation=~{gencode} --fusions=~{outputFileNamePrefix}.fusions.tsv \
      --output=~{outputFileNamePrefix}.fusions.pdf --alignments=~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam \
      --cytobands=~{cytobands} --proteinDomains=~{domains}
  >>>

  runtime {
    memory:  "~{jobMemory} GB"
    modules: "~{modules}"
    cpu:     "~{threads}"
    timeout: "~{timeout}"
  }

  output {
      File fusionPredictions        = "~{outputFileNamePrefix}.fusions.tsv"
      File fusionDiscarded          = "~{outputFileNamePrefix}.fusions.discarded.tsv"
      File fusionFigure             = "~{outputFileNamePrefix}.fusions.pdf"
  }

  meta {
    output_meta: {
      fusionPredictions: "Fusion output tsv",
      fusionDiscarded:   "Discarded fusion output tsv",
      fusionFigure: "PDF rendering of candidate fusions"
    }
  }
}

task runStarFusion {
  input {
    String modules = "star-fusion/1.8.1 star-fusion-genome/1.8.1-hg38"
    String genome = "$HG38_ROOT/hg38_random.fa"
    String outputFileNamePrefix
    Int threads = 8
    Int jobMemory = 64
    Int timeout = 72
  }

  parameter_meta {
    outputFileNamePrefix: "Prefix for filename"
    modules: "Names and versions of modules to load"
    genome: "Path to loaded genome"
    threads: "Requested CPU threads"
    jobMemory: "Memory allocated for this job"
    timeout: "Hours before task timeout"
  }

  command <<<
      set -euo pipefail

      STAR-Fusion --genome_lib_dir "~{genomeDir}"  \
               -J chimericOutJunction --examine_coding_effect \
               --CPU "~{threads}"
  >>>

  runtime {
    memory:  "~{jobMemory} GB"
    modules: "~{modules}"
    cpu:     "~{threads}"
    timeout: "~{timeout}"
  }

  output {
      File fusionPredictions        = "~{outputFileNamePrefix}.fusions.tsv"
      File fusionDiscarded          = "~{outputFileNamePrefix}.fusions.discarded.tsv"
      File spliceJunctions          = "~{outputFileNamePrefix}.SJ.out.tab"
      File sortAlignBam             = "~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam"
      File sortAlignIndex           = "~{outputFileNamePrefix}.Aligned.sortedByCoord.out.bam.bai"
      File fusionFigure             = "~{outputFileNamePrefix}.fusions.pdf"
  }

  meta {
    output_meta: {
      fusionPredictions: "Fusion output tsv",
      fusionDiscarded:   "Discarded fusion output tsv",
      spliceJunctions: "Splice junctions from star fusion run",
      sortAlignBam: "Output sorted bam file aligned to genome",
      sortAlignIndex: "Output index file for sorted bam aligned to genome",
      fusionFigure: "PDF rendering of candidate fusions"
    }
  }
}
