import appUnitTestSuite from '../../../test/List.test';
import deviceIntegrationTest from './DeviceIntegration.test';
import conversionIntegrationTest from './ConversionIntegration.test';

export default function testsuite() {
  appUnitTestSuite();
  deviceIntegrationTest();
  conversionIntegrationTest();
}
