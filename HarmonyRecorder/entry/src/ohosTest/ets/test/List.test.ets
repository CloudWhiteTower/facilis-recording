import appUnitTestSuite from '../../../test/List.test';
import deviceIntegrationTest from './DeviceIntegration.test';
import conversionIntegrationTest from './ConversionIntegration.test';
import v3IntegrationTest from './V3Integration.test';

export default function testsuite() {
  appUnitTestSuite();
  deviceIntegrationTest();
  conversionIntegrationTest();
  v3IntegrationTest();
}
