#!/usr/bin/env ruby

OUTPUT_DIRECTORY='mkv-in-merge.out'
KNOWN_FORMATS = ['mkv', 'avi', 'mp4']
KNOWN_SUBS = ['ass', 'ssa', 'srt', 'sub']

#def fonts_to_attach
#   find -name "*.ttf" -exec echo --attach-file "\"{}\"" \;
#end

def videos
  KNOWN_FORMATS.each do |format|
    files = Dir.glob("*.#{format}")
    return files if files
  end
end

def get_subtitles(episode)
  KNOWN_SUBS.each {|ext| "#{episode}.#{ext}" if File.exists("#{episode}.#{ext}")}
end

def get_episode(video)
  video.chomp(File.extname(video))
end

videos.each do |video|
  episode = get_episode(video)
  subtitles = get_subtitles(episode)

  args = ['mkvmerge']
  # TODO: pass other options
  args.push(video)
  args.push(subtitles) if subtitles
  args.push('-o', "#{OUTPUT_DIRECTORY}/#{episode}.mkv")

  system(*args)
end

