#!/bin/env ruby
# encoding: utf-8

require 'colorize'
require 'mediawiki_api'
require 'nokogiri'
require 'open-uri'
require 'scraperwiki'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

class Parser

  def initialize(h)
    @url = h[:url]
  end

  def noko
    @noko ||= Nokogiri::HTML(open(@url).read)
  end

  def district_top_row
    noko.xpath(".//table[.//th[1][contains(.,'Candidate')]]/tr[td][1]").map do |tr|
      tds = tr.css('td')
      winner = tds[0].text.match(/(.*) \((.*)\)/) or raise "Odd format: #{tds[0].text}"
      name, party = winner.captures
      {
        name: name,
        wikipedia__en: tds[0].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: tr.xpath('preceding::li/b').last.text,
        party: party,
      }
    end
  end

  def district_top_row_2015
    noko.xpath(".//table[.//caption[contains(.,'District')]]/tr[td][1]").map do |tr|
      tds = tr.css('td')
      {
        name: tds[0].text.strip,
        wikipedia__en: tds[0].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: tr.parent.css('caption').text[/(\w+) District/],
        party: tds[1].text.strip,
      }
    end
  end

  def at_large_2015
    noko.xpath(".//table[.//caption[contains(.,'At large')]]/tr[td[b]]").map do |tr|
      tds = tr.css('td')
      {
        name: tds[0].text.strip,
        wikipedia__en: tds[0].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: "At large",
        party: tds[1].text.strip,
      }
    end
  end

  def polling_divisions_top_row
    noko.xpath(".//table[.//th[1][contains(.,'Candidate')]]/tr[td][2]").map do |tr|
      tds = tr.css('td')
      winner = tds[0].text.match(/(.*) \((.*)\)/) or raise "Odd format: #{tds[0].text}"
      name, party = winner.captures
      {
        name: name,
        wikipedia__en: tds[0].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: tr.xpath('preceding::p/b').last.text,
        party: party,
      }
    end
  end

  def district_top_row_2003
    noko.xpath(".//table[.//th[1][contains(.,'Candidate')]]/tr[td][1]").map do |tr|
      tds = tr.css('td')
      winner = tds[0].text.match(/(.*) \((.*)\)/) or raise "Odd format: #{tds[0].text}"
      name, party = winner.captures
      {
        name: name,
        wikipedia__en: tds[0].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: tr.xpath('preceding::p/b').last.text,
        party: party,
      }
    end
  end

  def district_grid
    noko.xpath(".//table[.//th[1][contains(.,'Constituency')]]/tr[contains(td[1],' District')]").map do |tr|
      tds = tr.css('td')
      winner = tds[1].text.match(/(.*) \((.*)\)/) or raise "Odd format: #{tds[0].text}"
      name, party = winner.captures
      {
        name: name,
        wikipedia__en: tds[1].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: tds[0].text[/(\w+ District)/, 1],
        party: party,
      }
    end
  end

  def at_large_bold
    noko.xpath(".//table[.//th[1][contains(.,'Position')]]/tr[td[b]]").map do |tr|
      tds = tr.css('td')
      {
        name: tds[1].text.tidy,
        wikipedia__en: tds[1].xpath('.//a[not(@class="new")]/@title').text.strip,
        area: "At large",
        party: tds[2].text.tidy.gsub(/[\(\)]/,''),
      }
    end
  end

end

def id_for(m)
  [m[:wikipedia__en], m[:name]].find { |n| !n.to_s.empty? }.downcase.gsub(/[[:space:]]/,'_')
end

terms = {
  district_top_row: [ 2011, 2007 ],
  district_top_row_2003: [ 2003, 1999, 1995 ],
  district_top_row_2015: [ 2015 ],
  polling_divisions_top_row: [ 1990, 1986 ],
  district_grid: [ 1983, 1979, 1975, 1971 ],
  at_large_bold: [ 2011, 2007, 2003, 1999, 1995 ],
  at_large_2015: [ 2015 ],
}

def area_from(str)
  return { area_id: 'none', area: 'At large' } if str.downcase == 'at large'

  if str[/^(\d)[snrt][tdh] District/]
    id = $1
  elsif str[/^(\w+) Electoral District/i]
    id = %w(First Second Third Fourth Fifth Sixth Seventh Eighth Ninth).find_index($1) + 1
  else 
    raise "Odd area: #{str}"
  end
  return { area_id: id, area: "District #{id}" }
end


terms.each do |meth, ts|
  ts.each do |t|
    next unless t == 2015
    url = "https://en.wikipedia.org/wiki/British_Virgin_Islands_general_election,_%s" % t
    data = Parser.new(url: url).send(meth).map { |m| 
      m.merge(area_from(m[:area])).merge(term: t, source: url, id: id_for(m)) 
    }
    ScraperWiki.save_sqlite([:id, :area, :term], data)
  end
end
