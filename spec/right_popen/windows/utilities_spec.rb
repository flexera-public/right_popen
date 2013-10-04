require ::File.expand_path('../../../spec_helper', __FILE__)
require 'right_popen/windows/utilities'

describe RightScale::RightPopen::Windows::Utilities do
  let(:described_module) { RightScale::RightPopen::Windows::Utilities }

  subject { described_module }

  context '.merge_environment' do
    let(:custom_key_a)   { 'RsUtilitiesSpec_customA' }
    let(:custom_key_b)   { 'RsUtilitiesSpec_customB' }
    let(:custom_value_a) { custom_key_a + ' value' }
    let(:custom_value_b) { custom_key_b + ' value' }
    let(:machine_key)    { 'RsUtilitiesSpec_MACHINE' }
    let(:machine_value)  { machine_key + ' value' }
    let(:process_key)    { 'RsUtilitiesSpec_PROCESS' }
    let(:process_value)  { process_key + ' value' }
    let(:user_key)       { 'RsUtilitiesSpec_USER' }
    let(:user_value)     { user_key + ' value' }

    let(:custom_environment_hash) do
      { custom_key_a => custom_value_a, custom_key_b => custom_value_b }
    end

    let(:machine_environment_hash) { { machine_key => machine_value } }
    let(:user_environment_hash)    { { user_key => user_value } }

    let(:expected_merged_hash) do
      {}.merge(::ENV).merge(
        custom_key_a  => custom_value_a,
        custom_key_b  => custom_value_b,
        machine_key   => machine_value,
        user_key      => user_value)
    end

    before(:each) do
      @old_values = {
        custom_key_a =>  ::ENV[custom_key_a],
        custom_key_b =>  ::ENV[custom_key_b],
        machine_key =>   ::ENV[machine_key],
        process_key =>   ::ENV[process_key],
        user_key =>      ::ENV[user_key]
      }
      ::ENV[custom_key_a]  = nil
      ::ENV[custom_key_b]  = nil
      ::ENV[machine_key]   = nil
      ::ENV[process_key]   = process_value
      ::ENV[user_key]      = nil
    end

    after(:each) do
      @old_values.each_key { |k| ::ENV[k] = @old_values[k] }
    end

    it 'should merge environment hashes' do
      actual_merged_hash = subject.merge_environment(
        custom_environment_hash,
        user_environment_hash,
        machine_environment_hash)
      actual_merged_hash.should == expected_merged_hash
    end

    it 'should merge env var keys case insensitively (on Windows)' do
      ENV[custom_key_a.downcase] = 'should be overwritten thrice'
      machine_environment_hash[custom_key_a] = 'should be overwritten twice'
      user_environment_hash[custom_key_a.upcase] = 'should be overwritten once'
      actual_merged_hash = subject.merge_environment(
        custom_environment_hash,
        user_environment_hash,
        machine_environment_hash)

      # the key is inserted into the hash only once using the original case.
      # thereafter the value gets overwritten but the case of the key does not
      # change so the first case is what appears.
      actual_merged_hash[custom_key_a.downcase].should == custom_value_a
      actual_merged_hash[custom_key_a.upcase].should == nil
      actual_merged_hash[custom_key_a].should == nil
      expected_merged_hash.delete(custom_key_a)
      expected_merged_hash[custom_key_a.downcase] = custom_value_a
      actual_merged_hash.should == expected_merged_hash
    end

    context 'given blacklisted env vars' do
      let(:blacked_a)     { 'TEMP' }
      let(:blacked_b)     { 'ComSpec' }
      let(:blacked_value) { 'c:/blacklisted/key' }

      it 'should not merge blacklisted env vars from machine or user' do
        actual_merged_hash = subject.merge_environment(
          custom_environment_hash,
          user_environment_hash,
          machine_environment_hash)
        actual_merged_hash.values.should_not include(blacked_value)
        actual_merged_hash[blacked_a].should == ::ENV[blacked_a]
        actual_merged_hash[blacked_b].should == ::ENV[blacked_b]
        actual_merged_hash.should == expected_merged_hash
      end
    end # given blacklisted env vars

  end # merge_environment

  context '.environment_hash_to_string_block' do
    let(:environment_hash) do
      { 'abc' => 'abc value', 'DEF' => 'def value'}
    end

    it 'should convert hash to string block' do
      actual = subject.environment_hash_to_string_block(environment_hash)
      expected = "DEF=def value\x00abc=abc value\x00\x00"  # keys are sorted case-sensitively first
      actual.should == expected
    end
  end

  context '.string_block_to_environment_hash' do
    let(:string_block) { "one=value 1\x00two=value 2\x00\x00" }

    it 'should convert string block to hash' do
      actual = subject.string_block_to_environment_hash(string_block)
      expected = { 'one' => 'value 1', 'two' => 'value 2' }
      actual.should == expected
    end
  end

end # RightScale::RightPopen::Windows::Utilities
